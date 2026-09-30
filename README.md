# LUnit CLI

LUnit was designed to easily and natively integrate into continuous integration (CI) pipelines.
To achieve this, a way of executing tests from the command line is needed and the results need to be available in a format which may be digested by the CI system.

## Executing Tests from the Command Line

The command line interface (CLI) has been migrated out of the main LUnit project.
The reason for this is that the CLI is installed on the system level and requires to be installed as administrator.
To install the native CLI, please use [this package](https://www.vipm.io/package/astemes_lib_lunit_cli/). 
There is also a G-CLI package, maintained by Sam at SAS Workshops, which can be found [here](https://www.vipm.io/package/sas_workshops_lib_lunit_for_g_cli/) (please note that this document does not apply the G-CLI).

### Installation

The package installs the LUnit operation into `<LabVIEW>/vi.lib/Astemes/LUnit CLI/LUnitCLI`.
A post-install step then copies it into the operations directory of the LabVIEW CLI, where `LabVIEWCLI -OperationName LUnit` finds it without further arguments:

|OS|LabVIEW CLI operations directory|
|---|---|
|Windows|`C:\Program Files (x86)\National Instruments\Shared\LabVIEW CLI\Operations`|
|Linux|`/usr/local/natinst/nilvcli/Operations`|
|macOS|`/Library/Application Support/National Instruments/LabVIEW CLI/Operations`|

Writing to this directory requires administrator privileges on Windows and root on Linux and macOS, so VIPM must be run as administrator (or root).
The post-install step runs inside LabVIEW, not inside VIPM.
If LabVIEW is already running when the package is installed, VIPM uses that instance and the step runs with its privileges, so close LabVIEW before installing to let VIPM start it with administrator privileges.
Uninstalling the package removes the copy again.

### Using the CLI without administrator privileges

If the package is installed without the privileges needed to write to the operations directory, the installation still succeeds, but the post-install step reports a warning that the operation could not be registered with the LabVIEW CLI.
The operation can then be used by pointing the LabVIEW CLI at the installed copy with the `-AdditionalOperationDirectory` argument:

```
LabVIEWCLI -OperationName LUnit -AdditionalOperationDirectory "<LabVIEW>/vi.lib/Astemes/LUnit CLI" -Path "<path-to-tests>" -ReportPath "<report-path>.xml"
```

where `<LabVIEW>` is the LabVIEW installation directory, for example `C:\Program Files\National Instruments\LabVIEW 2026` on Windows or `/usr/local/natinst/LabVIEW-2026-64` on Linux.
This also works if LUnit CLI is installed into several LabVIEW versions, as each call can use the operation installed for the LabVIEW version it runs.

If the `-Headless` argument is used, it must be the last argument.
The LabVIEW CLI otherwise ignores an `-AdditionalOperationDirectory` given after it and fails with error -350006, reporting that the operation cannot be found.

LUnit installs a command line operation using the LabVIEW native [LabVIEWCLI by NI](https://zone.ni.com/reference/en-XX/help/371361R-01/lvhowto/cli_running_operations/).
This operation is named LUnit and may be called using LabVIEWCLI -OperationName LUnit.
An example illustrating the usage of the CLI i provided at `...\LabVIEW 20XX\examples\Astemes\LUnit\LUnit CLI Demo.vi`.
A path to load tests from is provided using the -ProjectPath argument and the report directory is specified using the -ReportPath argument.

When executing tests from the command line, the test case index is cleared and re-created by default each time.
This ensures that all inherited test methods are detected*, at the expense of some overhead for test discovery.
The `-ClearIndex` flag may be used to override this behavior and re-use the index to improve the execution time.

|Argument|Description
|---|---|
|<nobr>`-Path`</nobr>|Specifies the path to the project, class or library containing the Test Case classes to run. If you provide a directory, all tests within this directory or sub directories will be executed|
|<nobr>`-Parallel`</nobr>|Specifies if tests are to be run in parallell. Valid values are  ``True`` or  ``False`` (case-insensitive) |
|<nobr>`-ReportPath`</nobr>|The output path for the report file generated. The execution generates either a .txt-file or an .xml-file, based on the path specified. If using multiple report formats, the path may be given as a comma separated list where the ordering of the elements in the list match the plugin order used in the `-CustomReports` argument. Please note that when configuring reporting plugins using the `-CustomReports` argument, this path can be given as a single directory where reports are saved using the default name for each plugin. |
|<nobr>`-ClearIndex`</nobr>|Clear the index and force LUnit to rediscover all tests. Default is ``True``. The index must be cleared to find new tests inherited for a Test Case. |
|<nobr>`-CustomReports`</nobr>| If there are custom report plugins installed, these can be activated by providing them as a comma separated list. If this is left empty, the default plugin will be selected based on the given file extenssion. If any of the built-in reporting formats (`Text Report` or `XML Report`) should stil be active, they should be added to the list. |

The LabVIEW CLI uses VI Server and by default it is configured to work on port 3363.
You will need to make sure that the connection is not blocked by firewalls.
As of version 1.6 of LUnit CLI, paths can be given as either relative or absolute.
Relative paths are resolved against the working directory of LabVIEW, which is the directory `LabVIEWCLI` was called from when the LabVIEW CLI launches LabVIEW.
If LabVIEW is already running when `LabVIEWCLI` is called, relative paths are resolved against the directory LabVIEW was started from, so use absolute paths in that case.

## Running on Linux and in Containers

LUnit CLI runs on Linux, including the official [NI LabVIEW Linux container](https://hub.docker.com/r/nationalinstruments/labview).
Install VIPM, LUnit and the LUnit CLI package as root while a headless LabVIEW is running, so that the post-install step can register the operation in `/usr/local/natinst/nilvcli/Operations`.
Then run the tests in a fresh container, with `-Headless` as the last argument:

```
LabVIEWCLI -OperationName LUnit \
  -LabVIEWPath /usr/local/natinst/LabVIEW-2026-64/labviewprofull \
  -Path "/workspace/<path-to-tests>" \
  -ReportPath "/workspace/lunit_reports/lunit.xml" \
  -LogToConsole TRUE \
  -Headless
```

Installing the packages in one container, committing it to an image and running each test run in a new container from that image avoids connection errors (-350000) between the LabVIEW CLI and a LabVIEW instance that was started by VIPM.

## Capturing the Test Results

Test results are saved in a text based format at the location specified when executing the command line operation.

LUnit has a built in xml-format for test reports which is using the same structure as the one used by JUnit testing framework and specified [here](https://llg.cubic.org/docs/junit/).
To use the JUnit xml format, you must provide a file path with the `.xml` extension.
Once the tests have finished, the result file is available at the specified path.
File may now be digested by most CI tools.
For Jenkins this is done using the [JUnit plugin](https://plugins.jenkins.io/junit/).

## Jenkins Example

Jenkins is a popular open source automation server used for continuous integration and delivery pipelines.
A pipeline in Jenkins may be configured using a declarative Jenkinsfile which may be saved directly in the repository.
Below is an example showing a basic configuration.

```java
pipeline {
	agent any
	environment{
		LV_PROJECT_PATH = "Path to Your LabVIEW Project.lvproj"
        LV_PORT = "3363"
	}
	stages {
		stage('Unit Tests') {
			steps {
				bat "LabVIEWCLI -OperationName LUnit -ProjectPath \"${WORKSPACE}\\${LV_PROJECT_PATH}\" -Parallel False -ReportPath \"${WORKSPACE}\\lunit_reports\\lunit.xml\" -ClearIndex TRUE -PortNumber ${LV_PORT} -LogFilePath \"${WORKSPACE}\\LabVIEWCLI_LUnit.txt\" -LogToConsole true -Verbosity Default"

				junit "lunit_reports\\*.xml"
			}
		}
	}
}
```

The pipeline above declares three environment variables used to configure the call to LUnit using the LabVIEW CLI.
The first is the path to the project file relative to the workspace, *i.e.* the path relative to the root of the repository where the Jenkinsfile is located.
The second is the number of parallel test runners to spawn, here configured to one. 
The third parameter is the port configured for VI server in LabVIEW under Tools->Options->VI Server.

The report is saved in the path `lunit_reports` using the file name `lunit.xml` with incrementing index.
After the execution of tests using the bat command the junit plugin is called to digest the report files generated.
This requires that the Jenkins JUnit plugin is installed, which it is by using the recommended default settings when installing Jenkins.

Note that this is a minimal example meant to demonstrate the concept. 
It could be improved significantly to reduce the details in the Jenkinsfile using shared libraries.
As an example, the build system used to build LUnit uses a simpler command `runLUnit "${LV_PROJECT_PATH}"` in the Jenkinsfile in stead of the rather detailed `bat` command.

## GitHub Actions Example

Another popular CI platform is Github Actions, which is the native CI environment for repositories hosted on GitHub.
Below is a minimal example of how to setup the 

```
name: Unit Tests
on:
  push:
jobs:
  checkout:
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v6
  test:
    needs: checkout
    steps:
      - run: |
          LabVIEWCLI `
            -OperationName LUnit `
            -Path "<path-to-directory-containing-tests>" `
            -Parallel False `
            -ReportPath "<test-log-directory>\LabVIEWCLI_LUnit.xml" `
            -ClearIndex True `
            -CustomReports "XML Report" `
            -Headless
        shell: pwsh
```

Note the `-Headless` argument is supported in [LabVIEW starting version 2026Q1](https://www.ni.com/docs/en-US/bundle/labview/page/running-operations-using-the-command-line-interface-for-labview.html) and makes it possible to run tests without activating LabVIEW.

### * Footnote on Test Finder indexing

The test finder keeps an index of all test methods for all test classes in the project.
When the test finder is started, it loads the index and compares all classes to the index.
If the classes has changed since the index was created, the class will be re-indexed.
As of version 1.0, the test indexer will however not re-index a class when a parent class has added a dynamic test method.
To detect new inherited dynamic method the test index must be re-created, which happens when the ``-ClearIndex`` flag is left at default value ``True``.
