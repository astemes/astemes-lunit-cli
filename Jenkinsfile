pipeline {
	agent {
        label 'LV2020'
    }
	environment{
		PROJECT_TITLE = "Astemes LUnit"
		REPO_URL = "https://github.com/astemes/astemes-lunit"
		AUTHOR = "Anton Sundqvist"
		INITIAL_RELEASE = 2021
		LV_PROJECT_PATH = "source\\LUnit Framework.lvproj"
		LV_BUILD_SPEC = "LUnit"
		LV_VIPB_PATH = "source\\LUnit.vipb"
		LV_CLI_VIPB_PATH = "source\\LUnit CLI.vipb"
		LV_VERSION = "20.0"
	}
	stages {
		stage('Initialize') {
			steps {
				library 'astemes-build-support'
				script{COMMIT_TAG = gitTag()}
				killLv()
				initWorkspace()
				dir("build_support"){
					pullBuildSupport()
					initPythonVenv "requirements.txt"
				}
			}
		}
		stage('Test') {
			steps {
				runLUnit "${LV_PROJECT_PATH}"
				junit "reports\\*.xml"
			}
		}
		stage('Build') {
			steps {
				clearMutationHistory "${WORKSPACE}\\source"
				//Execute LabVIEW build spec
				buildLVBuildSpec "${LV_PROJECT_PATH}", "${LV_BUILD_SPEC}"
				//Build mkdocs documentation
				buildDocs "${PROJECT_TITLE}", "${REPO_URL}", "${AUTHOR}", "${INITIAL_RELEASE}"
			}
		}
		stage('Deploy') {
			when{
				expression{
					!COMMIT_TAG.isEmpty()
				}
			}
			environment{
				GITHUB_TOKEN = credentials('github-token')
			}
			steps{
				//Build VIPM package
				script{VIP_FILE_PATH = buildVIPackage "${LV_VIPB_PATH}", "${LV_VERSION}", "${COMMIT_TAG}"}
				script{CLI_VIP_FILE_PATH = buildVIPackage "${LV_CLI_VIPB_PATH}", "${LV_VERSION}", "${COMMIT_TAG}"}
				deployGithubPages()
				deployGithubRelease "${REPO_URL}", "${COMMIT_TAG}", "${VIP_FILE_PATH}"
				addFileToGithubRelease "${REPO_URL}", "${COMMIT_TAG}", "${CLI_VIP_FILE_PATH}"
			}
		}
	}
	post{
        always { 
			killLv()
            //cleanWs(notFailBuild: true)
		}
		regression{
			sendMail "anton.sundqvist@astemes.com"
		}
	}
	options {
		buildDiscarder(logRotator(daysToKeepStr: '3', numToKeepStr: '5'))
	}
}