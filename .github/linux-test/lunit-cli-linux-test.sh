#!/usr/bin/env bash
# =============================================================================
# End-to-end test of the LUnit CLI package inside the NI LabVIEW Linux container.
#
#   bash lunit-cli-linux-test.sh install        <path-to-.vip> <output-dir>
#   bash lunit-cli-linux-test.sh run-registered <output-dir>
#   bash lunit-cli-linux-test.sh run-additional <output-dir>
#
# install         Installs VIPM, LUnit and the LUnit CLI package (as root) and
#                 checks that the post-install action registered the operation
#                 in the LabVIEW CLI operations directory. The workflow commits
#                 the container to an image afterwards.
# run-registered  Runs the LUnit Basic Example through the registered operation.
# run-additional  Removes the registered copy and runs the example through
#                 -AdditionalOperationDirectory, the documented non-admin
#                 workaround.
#
# Each mode runs in a fresh container, like a CI worker image: LabVIEWCLI does
# not reliably connect to a LabVIEW launched in a container where VIPM's
# headless LabVIEW was running.
# =============================================================================
set -uo pipefail

MODE="$1"; shift
VIPM_DEB_URL="${VIPM_DEB_URL:-https://traffic.libsyn.com/secure/jkinc/vipm_26.3.0-3954_amd64.deb}"
LABVIEW_VERSION="${LABVIEW_VERSION:-2026}"
OPS=/usr/local/natinst/nilvcli/Operations

section() { echo; echo "=== $* ==="; }

LV_EXE=$(find /usr/local/natinst -name labviewprofull -type f 2>/dev/null | head -1)
if [ -z "$LV_EXE" ]; then echo "labviewprofull not found" >&2; exit 1; fi
LV_DIR=$(dirname "$LV_EXE")
LV_BIN="$LV_DIR/labview"
[ -x "$LV_BIN" ] || LV_BIN="$LV_EXE"
EXAMPLE="$LV_DIR/examples/Astemes/LUnit/Basic Example/Basic Example.lvproj"

install() {
  local vip="$1" out="$2"
  mkdir -p "$out"
  exec > >(tee "$out/install.log") 2>&1

  section "Environment"
  id
  echo "LabVIEW: $LV_EXE"
  ls -la "$OPS"

  section "Install VIPM"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends ca-certificates curl unzip xvfb procps >/dev/null
  curl -fsSL --retry 3 -o /tmp/vipm.deb "$VIPM_DEB_URL"
  dpkg -i /tmp/vipm.deb >/dev/null || apt-get install -f -y -qq --no-install-recommends >/dev/null
  vipm --version || true

  section "Start headless LabVIEW for VIPM"
  export VIPM_NONINTERACTIVE=1 VIPM_ASSUME_YES=1 NO_COLOR=1 CI=true
  export VIPM_TIMEOUT=900 VIPM_DESKTOP_LIVELINESS_TIMEOUT=900
  # VIPM's desktop engine cannot finish its startup handshake with this set.
  unset LV_RTE_HEADLESS
  export DISPLAY=:99
  Xvfb "$DISPLAY" -screen 0 1280x720x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
  mkdir -p /tmp/natinst
  echo "1" > /tmp/natinst/LVContainer.txt
  "$LV_BIN" --headless >/tmp/labview-headless.log 2>&1 &
  vipm refresh --force || echo "vipm refresh failed; continuing"

  section "Install LUnit"
  vipm --show-progress --labview-version "$LABVIEW_VERSION" --labview-bitness 64 install astemes_lib_lunit
  echo "exit=$?"

  section "Install LUnit CLI package: $vip"
  # The package must not set close_labview_before_install: VIPM cannot relaunch
  # LabVIEW inside the container to run the post-install action.
  vipm --show-progress --verbose --labview-version "$LABVIEW_VERSION" --labview-bitness 64 install "$vip"
  local result=$?
  echo "exit=$result"
  vipm list --installed || true

  section "Installed files"
  ls -laR "$LV_DIR/vi.lib/Astemes/LUnit CLI" || true
  ls -la "$OPS"

  section "Stop LabVIEW and VIPM before committing the image"
  pkill -f "$LV_DIR/labview" || true
  pkill -f vipm || true
  pkill Xvfb || true
  sleep 5

  section "Summary"
  if [ -f "$OPS/LUnitCLI/LUnit.lvclass" ]; then
    echo "post-install registered the operation: yes"
  else
    echo "post-install registered the operation: NO"
    result=1
  fi
  return $result
}

run_lunit() {
  local name="$1" out="$2"; shift 2
  mkdir -p "$out"
  exec > >(tee "$out/$name.log") 2>&1
  local report="$out/$name.xml"

  section "LabVIEWCLI $name"
  # Extra arguments go before -Headless: every working call in the NI and
  # LabVIEW-CI-with-Containers scripts keeps -Headless last.
  LabVIEWCLI -OperationName LUnit \
    -LabVIEWPath "$LV_EXE" \
    "$@" \
    -Path "$EXAMPLE" \
    -ReportPath "$report" \
    -ClearIndex TRUE \
    -LogToConsole TRUE \
    -Headless
  echo "LabVIEWCLI exit=$?"

  section "LabVIEWCLI log files"
  for f in /tmp/lvtemporary_*.log; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done

  section "Report"
  if [ -f "$report" ]; then
    cat "$report"
    return 0
  fi
  echo "No report at $report"
  return 1
}

diagnose() {
  local out="$1"
  mkdir -p "$out"
  exec > >(tee "$out/diagnose.log") 2>&1
  section "/usr/local/natinst"
  ls -la /usr/local/natinst
  section "Candidate <nishared> directories"
  for d in /usr/local/natinst/share /usr/local/natinst/shared /usr/local/natinst/nishared; do
    [ -e "$d" ] && { echo "--- $d"; ls -la "$d"; }
  done
  section "LabVIEW configuration mentioning shared paths"
  grep -ri 'shared' "$LV_DIR"/*.conf "$LV_DIR"/*.ini /etc/natinst 2>/dev/null | head -40 || true
  section "How NI's own operations reference CoreOperation"
  grep -h 'Type="Parent"' "$OPS"/*/*.lvclass 2>/dev/null | sort | uniq -c || true
  section "Installed LUnit class parent"
  grep -h 'Type="Parent"' "$OPS/LUnitCLI/LUnit.lvclass" || true
}

run_relative() {
  # Relative -Path and -ReportPath, resolved against the directory LabVIEWCLI is
  # called from - which is NOT LabVIEW's own working directory.
  local out="$1"
  mkdir -p "$out"
  exec > >(tee "$out/relative.log") 2>&1
  local work=/tmp/relative-work
  mkdir -p "$work/reports"
  cp -r "$(dirname "$EXAMPLE")" "$work/Basic Example"
  touch /tmp/relative-start
  cd "$work"
  echo "LabVIEWCLI started from: $(pwd)"
  section "LabVIEWCLI relative (cwd $work)"
  LabVIEWCLI -OperationName LUnit \
    -LabVIEWPath "$LV_EXE" \
    -Path "Basic Example/Basic Example.lvproj" \
    -ReportPath "reports/relative.xml" \
    -ClearIndex TRUE \
    -LogToConsole TRUE \
    -Headless
  echo "LabVIEWCLI exit=$?"
  section "Where did the relative report land?"
  find / -xdev -name 'relative.xml' -newer /tmp/relative-start 2>/dev/null
  section "LabVIEWCLI log files"
  for f in /tmp/lvtemporary_*.log; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done
  section "Report"
  if [ ! -f "$work/reports/relative.xml" ]; then
    echo "No report at $work/reports/relative.xml"
    return 1
  fi
  cp "$work/reports/relative.xml" "$out/relative.xml"
  cat "$out/relative.xml"
  # -ReportPath alone can land right by accident; the tests themselves must
  # have been loaded from the working directory too. The broken test in the
  # example reports its full VI path.
  section "Check that -Path was resolved against $work"
  if grep -q "$work/Basic Example/Dummy/Test Broken.vi" "$out/relative.xml"; then
    echo "Tests were loaded from $work: OK"
    return 0
  fi
  echo "Tests were NOT loaded from $work. VI paths in the report:"
  grep -o 'VI Path: [^<]*&lt;b&gt;[^&]*' "$out/relative.xml" || grep -o '/[^ <]*Test Broken.vi' "$out/relative.xml"
  return 1
}

case "$MODE" in
  install)
    install "$@" ;;
  diagnose)
    diagnose "$@" ;;
  run-registered)
    run_lunit registered "$@" ;;
  run-relative)
    run_relative "$@" ;;
  run-additional)
    rm -rf "$OPS/LUnitCLI"
    run_lunit additional "$@" -AdditionalOperationDirectory "$LV_DIR/vi.lib/Astemes/LUnit CLI" ;;
  run-additional-opdir)
    rm -rf "$OPS/LUnitCLI"
    run_lunit additional-opdir "$@" -AdditionalOperationDirectory "$LV_DIR/vi.lib/Astemes/LUnit CLI/LUnitCLI" ;;
  run-additional-renamed)
    # Hypothesis: the CLI wants <dir>/<OperationName>/, i.e. a folder named LUnit.
    rm -rf "$OPS/LUnitCLI"
    mkdir -p /tmp/ops
    cp -r "$LV_DIR/vi.lib/Astemes/LUnit CLI/LUnitCLI" /tmp/ops/LUnit
    run_lunit additional-renamed "$@" -AdditionalOperationDirectory /tmp/ops ;;
  masscompile)
    # List the VIs that are broken on Linux.
    out="$1"; mkdir -p "$out"
    exec > >(tee "$out/masscompile.log") 2>&1
    for dir in "$LV_DIR/vi.lib/Astemes/LUnit CLI"; do
      name=$(basename "$dir" | tr ' ' '_')
      section "Mass compile $dir"
      LabVIEWCLI -OperationName MassCompile -LabVIEWPath "$LV_EXE" \
        -DirectoryToCompile "$dir" -MassCompileLogFile "$out/masscompile-$name.txt" \
        -LogToConsole TRUE -Headless
      echo "LabVIEWCLI exit=$?"
      [ -f "$out/masscompile-$name.txt" ] && grep -iE 'bad|broken|error|missing|search' "$out/masscompile-$name.txt" | head -80
    done ;;
  *)
    echo "Unknown mode: $MODE" >&2; exit 2 ;;
esac
