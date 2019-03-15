#!/bin/bash

set -xe

export OS=$(uname)
if [ "${OS}" = "Linux" ]; then
    export DS_ROOT_TASK=${HOME}
fi;

if [ "${OS}" = "${TC_MSYS_VERSION}" ]; then
    export DS_ROOT_TASK=${TASKCLUSTER_TASK_DIR}
    export PLATFORM_EXE_SUFFIX=.exe
fi;

if [ "${OS}" = "Darwin" ]; then
    export DS_ROOT_TASK=${TASKCLUSTER_TASK_DIR}
    export SWIG_LIB="$(find ${DS_ROOT_TASK}/homebrew/Cellar/swig/ -type f -name "swig.swg" | xargs dirname)"

    # It seems chaining |export DYLD_LIBRARY_PATH=...| does not work, maybe
    # because of SIP? Who knows ...
    if [ ! -z "${EXTRA_ENV}" ]; then
        eval "export ${EXTRA_ENV}"
    fi;
fi;

export TASKCLUSTER_ARTIFACTS=${TASKCLUSTER_ARTIFACTS:-/tmp/artifacts}
export TASKCLUSTER_TMP_DIR=${TASKCLUSTER_TMP_DIR:-/tmp}

export ANDROID_TMP_DIR=/data/local/tmp

mkdir -p ${TASKCLUSTER_TMP_DIR} || true

export DS_TFDIR=${DS_ROOT_TASK}/DeepSpeech/tf
export DS_DSDIR=${DS_ROOT_TASK}/DeepSpeech/ds

export DS_VERSION="$(cat ${DS_DSDIR}/VERSION)"

export ANDROID_SDK_HOME=${DS_ROOT_TASK}/DeepSpeech/Android/SDK/
export ANDROID_NDK_HOME=${DS_ROOT_TASK}/DeepSpeech/Android/android-ndk-r18b/

TAR=${TAR:-"tar"}
XZ=${XZ:-"pixz -9"}
UNXZ=${UNXZ:-"pixz -d"}

if [ "${OS}" = "${TC_MSYS_VERSION}" ]; then
  TAR=/usr/bin/tar.exe
  XZ="xz -9 -T0 -c -"
  UNXZ="xz -9 -T0 -d"
fi

model_source="${DEEPSPEECH_TEST_MODEL}"
model_name="$(basename "${model_source}")"
model_name_mmap="$(basename -s ".pb" "${model_source}").pbmm"
model_source_mmap="$(dirname "${model_source}")/${model_name_mmap}"

SUPPORTED_PYTHON_VERSIONS=${SUPPORTED_PYTHON_VERSIONS:-2.7.15:ucs2 2.7.15:ucs4 3.4.9:ucs4 3.5.6:ucs4 3.6.7:ucs4 3.7.1:ucs4}
SUPPORTED_NODEJS_VERSIONS=${SUPPORTED_NODEJS_VERSIONS:-4.9.1 5.12.0 6.14.4 7.10.1 8.12.0 9.11.2 10.12.0 11.0.0}

strip() {
  echo "$(echo $1 | sed -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//')"
}

# This verify exact inference result
assert_correct_inference()
{
  phrase=$(strip "$1")
  expected=$(strip "$2")

  if [ -z "${phrase}" -o -z "${expected}" ]; then
      echo "One or more empty strings:"
      echo "phrase: <${phrase}>"
      echo "expected: <${expected}>"
      return 1
  fi;

  if [ "${phrase}" = "${expected}" ]; then
      echo "Proper output has been produced:"
      echo "${phrase}"
      return 0
  else
      echo "!! Non matching output !!"
      echo "got: <${phrase}>"
      echo "xxd:"; echo "${phrase}" | xxd
      echo "-------------------"
      echo "expected: <${expected}>"
      echo "xxd:"; echo "${expected}" | xxd
      return 1
  fi;
}

# This verify that ${expected} is contained within ${phrase}
assert_working_inference()
{
  phrase=$1
  expected=$2

  if [ -z "${phrase}" -o -z "${expected}" ]; then
      echo "One or more empty strings:"
      echo "phrase: <${phrase}>"
      echo "expected: <${expected}>"
      return 1
  fi;

  case "${phrase}" in
      *${expected}*)
          echo "Proper output has been produced:"
          echo "${phrase}"
          return 0
      ;;

      *)
          echo "!! Non matching output !!"
          echo "got: <${phrase}>"
          echo "xxd:"; echo "${phrase}" | xxd
          echo "-------------------"
          echo "expected: <${expected}>"
          echo "xxd:"; echo "${expected}" | xxd
          return 1
      ;;
  esac
}

assert_shows_something()
{
  stderr=$1
  expected=$2

  if [ -z "${stderr}" -o -z "${expected}" ]; then
      echo "One or more empty strings:"
      echo "stderr: <${stderr}>"
      echo "expected: <${expected}>"
      return 1
  fi;

  case "${stderr}" in
      *${expected}*)
          echo "Proper output has been produced:"
          echo "${stderr}"
          return 0
      ;;

      *)
          echo "!! Non matching output !!"
          echo "got: <${stderr}>"
          echo "xxd:"; echo "${stderr}" | xxd
          echo "-------------------"
          echo "expected: <${expected}>"
          echo "xxd:"; echo "${expected}" | xxd
          return 1
      ;;
  esac
}

assert_not_present()
{
  stderr=$1
  not_expected=$2

  if [ -z "${stderr}" -o -z "${not_expected}" ]; then
      echo "One or more empty strings:"
      echo "stderr: <${stderr}>"
      echo "not_expected: <${not_expected}>"
      return 1
  fi;

  case "${stderr}" in
      *${not_expected}*)
          echo "!! Not expected was present !!"
          echo "got: <${stderr}>"
          echo "xxd:"; echo "${stderr}" | xxd
          echo "-------------------"
          echo "not_expected: <${not_expected}>"
          echo "xxd:"; echo "${not_expected}" | xxd
          return 1
      ;;

      *)
          echo "Proper not expected output has not been produced:"
          echo "${stderr}"
          return 0
      ;;
  esac
}

assert_correct_ldc93s1()
{
  assert_correct_inference "$1" "she had your dark suit in greasy wash water all year"
}

assert_working_ldc93s1()
{
  assert_working_inference "$1" "she had your dark suit in greasy wash water all year"
}

assert_correct_ldc93s1_lm()
{
  assert_correct_inference "$1" "she had your dark suit in greasy wash water all year"
}

assert_working_ldc93s1_lm()
{
  assert_working_inference "$1" "she had your dark suit in greasy wash water all year"
}

assert_correct_multi_ldc93s1()
{
  assert_shows_something "$1" "/LDC93S1.wav%she had your dark suit in greasy wash water all year%"
  assert_shows_something "$1" "/LDC93S1_pcms16le_2_44100.wav%she had your dark suit in greasy wash water all year%"
  ## 8k will output garbage anyway ...
  # assert_shows_something "$1" "/LDC93S1_pcms16le_1_8000.wav%she hayorasryrtl lyreasy asr watal w water all year%"
}

assert_correct_ldc93s1_prodmodel()
{
  assert_correct_inference "$1" "she had a due and greasy wash water year"
}

assert_correct_ldc93s1_prodmodel_stereo_44k()
{
  assert_correct_inference "$1" "she had a due and greasy wash water year"
}

assert_correct_warning_upsampling()
{
  assert_shows_something "$1" "erratic speech recognition"
}

assert_tensorflow_version()
{
  assert_shows_something "$1" "${EXPECTED_TENSORFLOW_VERSION}"
}

assert_deepspeech_version()
{
  assert_not_present "$1" "DeepSpeech: unknown"
}

check_tensorflow_version()
{
  set +e
  ds_help=$(${DS_BINARY_PREFIX}deepspeech 2>&1 1>/dev/null)
  set -e

  assert_tensorflow_version "${ds_help}"
  assert_deepspeech_version "${ds_help}"
}

run_tflite_basic_inference_tests()
{
  phrase_pbmodel_nolm=$(${DS_BINARY_PREFIX}deepspeech --model ${ANDROID_TMP_DIR}/ds/${model_name} --alphabet ${ANDROID_TMP_DIR}/ds/alphabet.txt --audio ${ANDROID_TMP_DIR}/ds/LDC93S1.wav)
  assert_correct_ldc93s1 "${phrase_pbmodel_nolm}"
}

run_netframework_inference_tests()
{
  phrase_pbmodel_nolm=$(DeepSpeechConsole.exe --model ${TASKCLUSTER_TMP_DIR}/${model_name} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav)
  assert_working_ldc93s1 "${phrase_pbmodel_nolm}"

  phrase_pbmodel_nolm=$(DeepSpeechConsole.exe --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav)
  assert_working_ldc93s1 "${phrase_pbmodel_nolm}"

  phrase_pbmodel_withlm=$(DeepSpeechConsole.exe --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --lm ${TASKCLUSTER_TMP_DIR}/lm.binary --trie ${TASKCLUSTER_TMP_DIR}/trie --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav)
  assert_working_ldc93s1_lm "${phrase_pbmodel_withlm}"
}

run_basic_inference_tests()
{
  phrase_pbmodel_nolm=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav)
  assert_correct_ldc93s1 "${phrase_pbmodel_nolm}"

  phrase_pbmodel_nolm=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav)
  assert_correct_ldc93s1 "${phrase_pbmodel_nolm}"

  phrase_pbmodel_withlm=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --lm ${TASKCLUSTER_TMP_DIR}/lm.binary --trie ${TASKCLUSTER_TMP_DIR}/trie --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav)
  assert_correct_ldc93s1_lm "${phrase_pbmodel_withlm}"
}

run_all_inference_tests()
{
  run_basic_inference_tests

  phrase_pbmodel_nolm_stereo_44k=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1_pcms16le_2_44100.wav)
  assert_correct_ldc93s1 "${phrase_pbmodel_nolm_stereo_44k}"

  phrase_pbmodel_withlm_stereo_44k=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --lm ${TASKCLUSTER_TMP_DIR}/lm.binary --trie ${TASKCLUSTER_TMP_DIR}/trie --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1_pcms16le_2_44100.wav)
  assert_correct_ldc93s1_lm "${phrase_pbmodel_withlm_stereo_44k}"

  phrase_pbmodel_nolm_mono_8k=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1_pcms16le_1_8000.wav 2>&1 1>/dev/null)
  assert_correct_warning_upsampling "${phrase_pbmodel_nolm_mono_8k}"

  phrase_pbmodel_withlm_mono_8k=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --lm ${TASKCLUSTER_TMP_DIR}/lm.binary --trie ${TASKCLUSTER_TMP_DIR}/trie --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1_pcms16le_1_8000.wav 2>&1 1>/dev/null)
  assert_correct_warning_upsampling "${phrase_pbmodel_withlm_mono_8k}"
}

run_prod_inference_tests()
{
  phrase_pbmodel_withlm=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --lm ${TASKCLUSTER_TMP_DIR}/lm.binary --trie ${TASKCLUSTER_TMP_DIR}/trie --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav)
  assert_correct_ldc93s1_prodmodel "${phrase_pbmodel_withlm}"

  phrase_pbmodel_withlm=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --lm ${TASKCLUSTER_TMP_DIR}/lm.binary --trie ${TASKCLUSTER_TMP_DIR}/trie --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav)
  assert_correct_ldc93s1_prodmodel "${phrase_pbmodel_withlm}"

  phrase_pbmodel_withlm_stereo_44k=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --lm ${TASKCLUSTER_TMP_DIR}/lm.binary --trie ${TASKCLUSTER_TMP_DIR}/trie --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1_pcms16le_2_44100.wav)
  assert_correct_ldc93s1_prodmodel_stereo_44k "${phrase_pbmodel_withlm_stereo_44k}"

  phrase_pbmodel_withlm_mono_8k=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --lm ${TASKCLUSTER_TMP_DIR}/lm.binary --trie ${TASKCLUSTER_TMP_DIR}/trie --audio ${TASKCLUSTER_TMP_DIR}/LDC93S1_pcms16le_1_8000.wav 2>&1 1>/dev/null)
  assert_correct_warning_upsampling "${phrase_pbmodel_withlm_mono_8k}"
}

run_multi_inference_tests()
{
  multi_phrase_pbmodel_nolm=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --audio ${TASKCLUSTER_TMP_DIR}/ | tr '\n' '%')
  assert_correct_multi_ldc93s1 "${multi_phrase_pbmodel_nolm}"

  multi_phrase_pbmodel_withlm=$(deepspeech --model ${TASKCLUSTER_TMP_DIR}/${model_name} --alphabet ${TASKCLUSTER_TMP_DIR}/alphabet.txt --lm ${TASKCLUSTER_TMP_DIR}/lm.binary --trie ${TASKCLUSTER_TMP_DIR}/trie --audio ${TASKCLUSTER_TMP_DIR}/ | tr '\n' '%')
  assert_correct_multi_ldc93s1 "${multi_phrase_pbmodel_withlm}"
}

android_run_tests()
{
  cd ${DS_DSDIR}/native_client/java/

  adb shell service list

  adb shell ls -hal /data/local/tmp/test/

  ./gradlew --console=plain libdeepspeech:connectedAndroidTest
}

generic_download_tarxz()
{
  target_dir=$1
  url=$2

  if [ -z "${target_dir}" -o -z "${url}" ]; then
    echo "Empty name for target directory or URL:"
    echo " target_dir=${target_dir}"
    echo " url=${url}"
    exit 1
  fi;

  mkdir -p ${target_dir} || true

  wget ${url} -O - | ${UNXZ} | ${TAR} -C ${target_dir} -xf -
}

download_native_client_files()
{
  generic_download_tarxz "$1" "${DEEPSPEECH_ARTIFACTS_ROOT}/native_client.tar.xz"
}

install_nuget()
{
  PROJECT_NAME=$1
  if [ -z "${PROJECT_NAME}" ]; then
    exit "Please call with a valid PROJECT_NAME"
    exit 1
  fi;

  nuget="${PROJECT_NAME}.${DS_VERSION}.nupkg"

  export PATH=$PATH:$(cygpath ${ChocolateyInstall})/bin

  mkdir -p "${TASKCLUSTER_TMP_DIR}/repo/"
  mkdir -p "${TASKCLUSTER_TMP_DIR}/ds/"

  wget -O - "${DEEPSPEECH_ARTIFACTS_ROOT}/${nuget}" | gunzip > "${TASKCLUSTER_TMP_DIR}/${PROJECT_NAME}.${DS_VERSION}.nupkg"
  wget -O - "${DEEPSPEECH_ARTIFACTS_ROOT}/DeepSpeechConsole.exe" | gunzip > "${TASKCLUSTER_TMP_DIR}/ds/DeepSpeechConsole.exe"

  nuget sources add -Name repo -Source $(cygpath -w "${TASKCLUSTER_TMP_DIR}/repo/")

  cd "${TASKCLUSTER_TMP_DIR}"
  nuget add $(cygpath -w "${TASKCLUSTER_TMP_DIR}/${nuget}") -source repo

  cd "${TASKCLUSTER_TMP_DIR}/ds/"
  nuget list -Source repo -Prerelease
  nuget install ${PROJECT_NAME} -Source repo -Prerelease

  ls -halR "${PROJECT_NAME}.${DS_VERSION}"

  nuget install NAudio
  cp NAudio*/lib/net35/NAudio.dll ${TASKCLUSTER_TMP_DIR}/ds/
  cp ${PROJECT_NAME}.${DS_VERSION}/build/libdeepspeech.so ${TASKCLUSTER_TMP_DIR}/ds/
  cp ${PROJECT_NAME}.${DS_VERSION}/lib/net462/DeepSpeechClient.dll ${TASKCLUSTER_TMP_DIR}/ds/

  ls -hal ${TASKCLUSTER_TMP_DIR}/ds/

  export PATH=${TASKCLUSTER_TMP_DIR}/ds/:$PATH
}

download_data()
{
  wget -P "${TASKCLUSTER_TMP_DIR}" "${model_source}"
  wget -P "${TASKCLUSTER_TMP_DIR}" "${model_source_mmap}"
  cp ${DS_ROOT_TASK}/DeepSpeech/ds/data/smoke_test/*.wav ${TASKCLUSTER_TMP_DIR}/
  cp ${DS_ROOT_TASK}/DeepSpeech/ds/data/alphabet.txt ${TASKCLUSTER_TMP_DIR}/alphabet.txt
  cp ${DS_ROOT_TASK}/DeepSpeech/ds/data/smoke_test/vocab.pruned.lm ${TASKCLUSTER_TMP_DIR}/lm.binary
  cp ${DS_ROOT_TASK}/DeepSpeech/ds/data/smoke_test/vocab.trie ${TASKCLUSTER_TMP_DIR}/trie
}

download_material()
{
  target_dir=$1

  download_native_client_files "${target_dir}"
  download_data

  ls -hal ${TASKCLUSTER_TMP_DIR}/${model_name} ${TASKCLUSTER_TMP_DIR}/${model_name_mmap} ${TASKCLUSTER_TMP_DIR}/LDC93S1*.wav ${TASKCLUSTER_TMP_DIR}/alphabet.txt
}

download_benchmark_model()
{
  target_dir=$1

  mkdir -p ${target_dir} || true

  wget -P "${target_dir}" "${model_source}"
  wget -P "${target_dir}" "${BENCHMARK_MODEL_BIN}" && chmod +x ${target_dir}/*benchmark_model
}

install_pyenv()
{
  if [ -z "${PYENV_ROOT}" ]; then
    echo "No PYENV_ROOT set";
    exit 1;
  fi;

  if [ ! -e "${PYENV_ROOT}/bin/pyenv" ]; then
    git clone --quiet https://github.com/pyenv/pyenv.git ${PYENV_ROOT}
    pushd ${PYENV_ROOT}
      git checkout --quiet 835707da2237b8f69560b2de27ae8ddd3e6cb1a4
    popd
  fi

  eval "$(pyenv init -)"
}

install_pyenv_virtualenv()
{
  PYENV_VENV=$1

  if [ -z "${PYENV_VENV}" ]; then
    echo "No PYENV_VENV set";
    exit 1;
  fi;

  if [ ! -e "${PYENV_VENV}/bin/pyenv-virtualenv" ]; then
    git clone --quiet https://github.com/pyenv/pyenv-virtualenv.git ${PYENV_VENV}
    pushd ${PYENV_VENV}
        git checkout --quiet 5419dc732066b035a28680475acd7b661c7c397d
    popd
  fi;

  eval "$(pyenv virtualenv-init -)"
}

maybe_install_xldd()
{
  # -s required to avoid the noisy output like "Entering / Leaving directories"
  toolchain=$(make -s -C ${DS_DSDIR}/native_client/ TARGET=${SYSTEM_TARGET} TFDIR=${DS_TFDIR} print-toolchain)
  if [ ! -x "${toolchain}ldd" ]; then
    cp "${DS_DSDIR}/native_client/xldd" "${toolchain}ldd" && chmod +x "${toolchain}ldd"
  fi
}

# Checks whether we run a patched version of bazel.
# Patching is required to dump computeKey() parameters to .ckd files
# See bazel.patch
# Return 0 (success exit code) on patched version, 1 on release version
is_patched_bazel()
{
  bazel_version=$(bazel version | grep 'Build label:' | cut -d':' -f2)

  bazel shutdown

  if [ -z "${bazel_version}" ]; then
    return 0;
  else
    return 1;
  fi;
}

verify_bazel_rebuild()
{
  bazel_explain_file="$1"

  if [ ! -f "${bazel_explain_file}" ]; then
    echo "No such explain file: ${bazel_explain_file}"
    exit 1
  fi;

  mkdir -p ${TASKCLUSTER_ARTIFACTS} || true

  cp ${DS_ROOT_TASK}/DeepSpeech/tf/bazel*.log ${TASKCLUSTER_ARTIFACTS}/

  spurious_rebuilds=$(grep 'Executing action' "${bazel_explain_file}" | grep 'Compiling' | grep -v -E 'no entry in the cache|unconditional execution is requested' | wc -l)
  if [ "${spurious_rebuilds}" -ne 0 ]; then
    echo "Bazel rebuilds some file it should not, please check."

    if is_patched_bazel; then
      mkdir -p ${DS_ROOT_TASK}/DeepSpeech/ckd/ds ${DS_ROOT_TASK}/DeepSpeech/ckd/tf
      tar xf ${DS_ROOT_TASK}/DeepSpeech/bazel-ckd-tf.tar --strip-components=4 -C ${DS_ROOT_TASK}/DeepSpeech/ckd/ds/
      tar xf ${DS_ROOT_TASK}/DeepSpeech/bazel-ckd-ds.tar --strip-components=4 -C ${DS_ROOT_TASK}/DeepSpeech/ckd/tf/

      echo "Making a diff between CKD files"
      mkdir -p ${TASKCLUSTER_ARTIFACTS}
      diff -urNw ${DS_ROOT_TASK}/DeepSpeech/ckd/tf/ ${DS_ROOT_TASK}/DeepSpeech/ckd/ds/ | tee ${TASKCLUSTER_ARTIFACTS}/ckd.diff

      rm -fr ${DS_ROOT_TASK}/DeepSpeech/ckd/tf/ ${DS_ROOT_TASK}/DeepSpeech/ckd/ds/
    else
      echo "Cannot get CKD information from release, please use patched Bazel"
    fi;

    exit 1
  fi;
}

# Should be called from context where Python virtualenv is set
verify_ctcdecoder_url()
{
  default_url=$(python util/taskcluster.py --decoder)
  echo "${default_url}" | grep -F "deepspeech.native_client.v${DS_VERSION}"
  rc_default_url=$?

  tag_url=$(python util/taskcluster.py --decoder --branch 'v1.2.3')
  echo "${tag_url}" | grep -F "deepspeech.native_client.v1.2.3"
  rc_tag_url=$?

  master_url=$(python util/taskcluster.py --decoder --branch 'master')
  echo "${master_url}" | grep -F "deepspeech.native_client.master"
  rc_master_url=$?

  if [ ${rc_default_url} -eq 0 -a ${rc_tag_url} -eq 0 -a ${rc_master_url} -eq 0 ]; then
    return 0
  else
    return 1
  fi;
}

do_bazel_build()
{
  cd ${DS_ROOT_TASK}/DeepSpeech/tf
  eval "export ${BAZEL_ENV_FLAGS}"

  if is_patched_bazel; then
    find ${DS_ROOT_TASK}/DeepSpeech/tf/bazel-out/ -iname "*.ckd" | tar -cf ${DS_ROOT_TASK}/DeepSpeech/bazel-ckd-tf.tar -T -
  fi;

  bazel ${BAZEL_OUTPUT_USER_ROOT} build \
    -s --explain bazel_monolithic.log --verbose_explanations --experimental_strict_action_env --config=monolithic -c opt ${BAZEL_BUILD_FLAGS} ${BAZEL_TARGETS}

  if is_patched_bazel; then
    find ${DS_ROOT_TASK}/DeepSpeech/tf/bazel-out/ -iname "*.ckd" | tar -cf ${DS_ROOT_TASK}/DeepSpeech/bazel-ckd-ds.tar -T -
  fi;

  verify_bazel_rebuild "${DS_ROOT_TASK}/DeepSpeech/tf/bazel_monolithic.log"
}

shutdown_bazel()
{
  cd ${DS_ROOT_TASK}/DeepSpeech/tf
  bazel ${BAZEL_OUTPUT_USER_ROOT} shutdown
}

do_bazel_shared_build()
{
  cd ${DS_ROOT_TASK}/DeepSpeech/tf
  eval "export ${BAZEL_ENV_FLAGS}"
  bazel ${BAZEL_OUTPUT_USER_ROOT} build \
    -s --explain bazel_shared.log --verbose_explanations --experimental_strict_action_env -c opt ${BAZEL_BUILD_FLAGS} ${BAZEL_TARGETS}
}

do_deepspeech_binary_build()
{
  cd ${DS_DSDIR}
  make -C native_client/ \
    TARGET=${SYSTEM_TARGET} \
    TFDIR=${DS_TFDIR} \
    RASPBIAN=${SYSTEM_RASPBIAN} \
    EXTRA_CFLAGS="${EXTRA_LOCAL_CFLAGS}" \
    EXTRA_LDFLAGS="${EXTRA_LOCAL_LDFLAGS}" \
    EXTRA_LIBS="${EXTRA_LOCAL_LIBS}" \
    deepspeech${PLATFORM_EXE_SUFFIX}
}

do_deepspeech_ndk_build()
{
  arch_abi=$1

  cd ${DS_DSDIR}/native_client/

  ${ANDROID_NDK_HOME}/ndk-build \
    APP_PLATFORM=android-21 \
    APP_BUILD_SCRIPT=$(pwd)/Android.mk \
    NDK_PROJECT_PATH=$(pwd) \
    APP_STL=c++_shared \
    TFDIR=${DS_TFDIR} \
    TARGET_ARCH_ABI=${arch_abi}
}

do_deepspeech_netframework_build()
{
  cd ${DS_DSDIR}/examples/net_framework/CSharpExamples

  # Setup dependencies
  nuget install DeepSpeechConsole/packages.config -OutputDirectory packages/
  nuget install DeepSpeechWPF/packages.config -OutputDirectory packages/

  MSBUILD="$(cygpath 'C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin\MSBuild.exe')"

  # We need MSYS2_ARG_CONV_EXCL='/' otherwise the '/' of CLI parameters gets mangled and disappears
  # We build the .NET Client for .NET Framework v4.5,v4.6,v4.7
  
  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechClient/DeepSpeechClient.csproj \
    /p:Configuration=Release \
    /p:Platform=x64 \
    /p:TargetFrameworkVersion="v4.5" \
    /p:OutputPath=bin/x64/Release/v4.5
	
  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechClient/DeepSpeechClient.csproj \
    /p:Configuration=Release \
    /p:Platform=x64 \
    /p:TargetFrameworkVersion="v4.6" \
    /p:OutputPath=bin/x64/Release/v4.6
	
  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechClient/DeepSpeechClient.csproj \
    /p:Configuration=Release \
    /p:Platform=x64 \
    /p:TargetFrameworkVersion="v4.7" \
    /p:OutputPath=bin/x64/Release/v4.7

  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechConsole/DeepSpeechConsole.csproj \
    /p:Configuration=Release \
    /p:Platform=x64

  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechWPF/DeepSpeech.WPF.csproj \
    /p:Configuration=Release \
    /p:Platform=x64
}

do_nuget_build()
{
  PROJECT_NAME=$1
  if [ -z "${PROJECT_NAME}" ]; then
    exit "Please call with a valid PROJECT_NAME"
    exit 1
  fi;

  cd ${DS_DSDIR}/examples/net_framework/CSharpExamples

  cp ${DS_TFDIR}/bazel-bin/native_client/libdeepspeech.so nupkg/build

  # We copy the generated clients for .NET into the Nuget framework dirs
  
  mkdir -p nupkg/lib/net45/
  cp DeepSpeechClient/bin/x64/Release/v4.5/DeepSpeechClient.dll nupkg/lib/net45/
  
  mkdir -p nupkg/lib/net46/
  cp DeepSpeechClient/bin/x64/Release/v4.6/DeepSpeechClient.dll nupkg/lib/net46/
  
  mkdir -p nupkg/lib/net47/
  cp DeepSpeechClient/bin/x64/Release/v4.7/DeepSpeechClient.dll nupkg/lib/net47/

  PROJECT_VERSION=$(shell cat ../../../VERSION | tr -d '\n' | tr -d '\r')
  sed \
    -e "s/\$NUPKG_ID/${PROJECT_NAME}/" \
    -e "s/\$NUPKG_VERSION/${PROJECT_VERSION}/" \
    nupkg/deepspeech.nuspec.in > nupkg/deepspeech.nuspec && cat nupkg/deepspeech.nuspec

  nuget pack nupkg/deepspeech.nuspec
}

# Hack to extract Ubuntu's 16.04 libssl 1.0.2 packages and use them during the
# local build of Python.
#
# Avoid (risky) upgrade of base system, allowing to keep one task build that
# builds all the python packages
maybe_ssl102_py37()
{
    pyver=$1

    unset PY37_OPENSSL
    unset PY37_LDPATH
    unset PY37_SOURCE_PACKAGE

    case "${pyver}" in
        3.7*)
            if [ "${OS}" = "Linux" ]; then
                PY37_OPENSSL_DIR=${DS_ROOT_TASK}/ssl-xenial

                if [ -d "${PY37_OPENSSL_DIR}" ]; then
                  rm -rf "${PY37_OPENSSL_DIR}"
                fi

                mkdir -p ${PY37_OPENSSL_DIR}
                wget -P ${TASKCLUSTER_TMP_DIR} \
                        http://${TASKCLUSTER_WORKER_GROUP}.ec2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl-dev_1.0.2g-1ubuntu4.15_amd64.deb \
                        http://${TASKCLUSTER_WORKER_GROUP}.ec2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.0.0_1.0.2g-1ubuntu4.15_amd64.deb

                for deb in ${TASKCLUSTER_TMP_DIR}/libssl*.deb; do
                    dpkg -x ${deb} ${PY37_OPENSSL_DIR}
                done;

                # Python configure expects things to be under lib/
                mv ${PY37_OPENSSL_DIR}/usr/include/x86_64-linux-gnu/openssl/opensslconf.h ${PY37_OPENSSL_DIR}/usr/include/openssl/
                mv ${PY37_OPENSSL_DIR}/lib/x86_64-linux-gnu/lib* ${PY37_OPENSSL_DIR}/usr/lib/
                mv ${PY37_OPENSSL_DIR}/usr/lib/x86_64-linux-gnu/* ${PY37_OPENSSL_DIR}/usr/lib/
                ln -sfn libcrypto.so.1.0.0 ${PY37_OPENSSL_DIR}/usr/lib/libcrypto.so
                ln -sfn libssl.so.1.0.0 ${PY37_OPENSSL_DIR}/usr/lib/libssl.so

                export PY37_OPENSSL="--with-openssl=${PY37_OPENSSL_DIR}/usr"
                export PY37_LDPATH="${PY37_OPENSSL_DIR}/usr/lib/"
            fi;

	    export NUMPY_BUILD_VERSION="==1.14.5"
	    export NUMPY_DEP_VERSION=">=1.14.5"
        ;;
    esac
}

do_deepspeech_python_build()
{
  cd ${DS_DSDIR}

  rename_to_gpu=$1

  unset PYTHON_BIN_PATH
  unset PYTHONPATH
  export PYENV_ROOT="${DS_ROOT_TASK}/DeepSpeech/.pyenv"
  export PATH="${PYENV_ROOT}/bin:$PATH"

  install_pyenv "${PYENV_ROOT}"
  install_pyenv_virtualenv "$(pyenv root)/plugins/pyenv-virtualenv"

  mkdir -p wheels

  SETUP_FLAGS=""
  if [ "${rename_to_gpu}" ]; then
    SETUP_FLAGS="--project_name deepspeech-gpu"
  fi

  for pyver_conf in ${SUPPORTED_PYTHON_VERSIONS}; do
    pyver=$(echo "${pyver_conf}" | cut -d':' -f1)
    pyconf=$(echo "${pyver_conf}" | cut -d':' -f2)

    export NUMPY_BUILD_VERSION="==1.7.0"
    export NUMPY_DEP_VERSION=">=1.7.0"

    maybe_ssl102_py37 ${pyver}

    LD_LIBRARY_PATH=${PY37_LDPATH}:$LD_LIBRARY_PATH PYTHON_CONFIGURE_OPTS="--enable-unicode=${pyconf} ${PY37_OPENSSL}" pyenv install ${pyver}

    pyenv virtualenv ${pyver} deepspeech
    source ${PYENV_ROOT}/versions/${pyver}/envs/deepspeech/bin/activate

    # Set LD path because python ssl might require it
    LD_LIBRARY_PATH=${PY37_LDPATH}:$LD_LIBRARY_PATH \
    EXTRA_CFLAGS="${EXTRA_LOCAL_CFLAGS}" \
    EXTRA_LDFLAGS="${EXTRA_LOCAL_LDFLAGS}" \
    EXTRA_LIBS="${EXTRA_LOCAL_LIBS}" \
    make -C native_client/python/ \
        TARGET=${SYSTEM_TARGET} \
        RASPBIAN=${SYSTEM_RASPBIAN} \
        TFDIR=${DS_TFDIR} \
        SETUP_FLAGS="${SETUP_FLAGS}" \
        bindings-clean bindings

    cp native_client/python/dist/*.whl wheels

    make -C native_client/python/ bindings-clean

    unset NUMPY_BUILD_VERSION
    unset NUMPY_DEP_VERSION

    deactivate
    pyenv uninstall --force deepspeech
    pyenv uninstall --force ${pyver}
  done;
}

do_deepspeech_decoder_build()
{
  cd ${DS_DSDIR}

  unset PYTHON_BIN_PATH
  unset PYTHONPATH
  export PYENV_ROOT="${DS_ROOT_TASK}/DeepSpeech/.pyenv"
  export PATH="${PYENV_ROOT}/bin:$PATH"

  install_pyenv "${PYENV_ROOT}"
  install_pyenv_virtualenv "$(pyenv root)/plugins/pyenv-virtualenv"

  mkdir -p wheels

  for pyver_conf in ${SUPPORTED_PYTHON_VERSIONS}; do
    pyver=$(echo "${pyver_conf}" | cut -d':' -f1)
    pyconf=$(echo "${pyver_conf}" | cut -d':' -f2)

    export NUMPY_BUILD_VERSION="==1.7.0"
    export NUMPY_DEP_VERSION=">=1.7.0"

    maybe_ssl102_py37 ${pyver}

    LD_LIBRARY_PATH=${PY37_LDPATH}:$LD_LIBRARY_PATH PYTHON_CONFIGURE_OPTS="--enable-unicode=${pyconf} ${PY37_OPENSSL}" pyenv install ${pyver}

    pyenv virtualenv ${pyver} deepspeech
    source ${PYENV_ROOT}/versions/${pyver}/envs/deepspeech/bin/activate

    # Set LD path because python ssl might require it
    LD_LIBRARY_PATH=${PY37_LDPATH}:$LD_LIBRARY_PATH \
    EXTRA_CFLAGS="${EXTRA_LOCAL_CFLAGS}" \
    EXTRA_LDFLAGS="${EXTRA_LOCAL_LDFLAGS}" \
    EXTRA_LIBS="${EXTRA_LOCAL_LIBS}" \
    make -C native_client/ctcdecode/ \
        TARGET=${SYSTEM_TARGET} \
        RASPBIAN=${SYSTEM_RASPBIAN} \
        TFDIR=${DS_TFDIR} \
        bindings

    cp native_client/ctcdecode/dist/*.whl wheels

    make -C native_client/ctcdecode clean-keep-common

    unset NUMPY_BUILD_VERSION
    unset NUMPY_DEP_VERSION

    deactivate
    pyenv uninstall --force deepspeech
    pyenv uninstall --force ${pyver}
  done;
}

do_deepspeech_nodejs_build()
{
  rename_to_gpu=$1

  npm update && npm install node-gyp node-pre-gyp

  export PATH="$(npm root)/.bin/:$PATH"

  for node in ${SUPPORTED_NODEJS_VERSIONS}; do
    EXTRA_CFLAGS="${EXTRA_LOCAL_CFLAGS}" EXTRA_LDFLAGS="${EXTRA_LOCAL_LDFLAGS}" EXTRA_LIBS="${EXTRA_LOCAL_LIBS}" make -C native_client/javascript \
      TARGET=${SYSTEM_TARGET} \
      RASPBIAN=${SYSTEM_RASPBIAN} \
      TFDIR=${DS_TFDIR} \
      NODE_ABI_TARGET=--target=$node \
      clean node-wrapper
  done;

  if [ "${rename_to_gpu}" ]; then
    make -C native_client/javascript clean npm-pack PROJECT_NAME=deepspeech-gpu
  else
    make -C native_client/javascript clean npm-pack
  fi

  tar -czf native_client/javascript/wrapper.tar.gz \
    -C native_client/javascript/ lib/
}

do_deepspeech_npm_package()
{
  cd ${DS_DSDIR}

  npm update && npm install node-gyp node-pre-gyp

  export PATH="$(npm root)/.bin/:$PATH"

  all_tasks="$(curl -s https://queue.taskcluster.net/v1/task/${TASK_ID} | python -c 'import json; import sys; print(" ".join(json.loads(sys.stdin.read())["dependencies"]));')"

  for dep in ${all_tasks}; do
    curl -L https://queue.taskcluster.net/v1/task/${dep}/artifacts/public/wrapper.tar.gz | tar -C native_client/javascript -xzvf -
  done;

  make -C native_client/javascript clean npm-pack
}

force_java_apk_x86_64()
{
  cd ${DS_DSDIR}/native_client/java/
  cat <<EOF > libdeepspeech/gradle.properties
ABI_FILTERS = x86_64
EOF
}

do_deepspeech_java_apk_build()
{
  cd ${DS_DSDIR}

  export ANDROID_HOME=${ANDROID_SDK_HOME}

  all_tasks="$(curl -s https://queue.taskcluster.net/v1/task/${TASK_ID} | python -c 'import json; import sys; print(" ".join(json.loads(sys.stdin.read())["dependencies"]));')"

  for dep in ${all_tasks}; do
    nc_arch="$(curl -s https://queue.taskcluster.net/v1/task/${dep} | python -c 'import json; import sys; print(json.loads(sys.stdin.read())["extra"]["nc_asset_name"])' | cut -d'.' -f2)"
    nc_dir=""

    # if a dep is included that has no "nc_asset_name" then it will be empty, just skip
    # this is required for running test-apk-android-x86_64-opt because of the training dep
    if [ ! -z "${nc_arch}" ]; then
      if [ "${nc_arch}" = "arm64" ]; then
        nc_dir="arm64-v8a"
      fi;

      if [ "${nc_arch}" = "armv7" ]; then
        nc_dir="armeabi-v7a"
      fi;

      if [ "${nc_arch}" = "x86_64" ]; then
        nc_dir="x86_64"
      fi;

      mkdir native_client/java/libdeepspeech/libs/${nc_dir}

      curl -L https://queue.taskcluster.net/v1/task/${dep}/artifacts/public/native_client.tar.xz | tar -C native_client/java/libdeepspeech/libs/${nc_dir}/ -Jxvf - libdeepspeech.so
    fi;
  done;

  make -C native_client/java/

  make -C native_client/java/ maven-bundle
}

package_native_client()
{
  tensorflow_dir=${DS_TFDIR}
  deepspeech_dir=${DS_DSDIR}
  artifacts_dir=${TASKCLUSTER_ARTIFACTS}
  artifact_name=$1

  if [ ! -d ${tensorflow_dir} -o ! -d ${deepspeech_dir} -o ! -d ${artifacts_dir} ]; then
    echo "Missing directory. Please check:"
    echo "tensorflow_dir=${tensorflow_dir}"
    echo "deepspeech_dir=${deepspeech_dir}"
    echo "artifacts_dir=${artifacts_dir}"
    exit 1
  fi;

  if [ -z "${artifact_name}" ]; then
    echo "Please specify artifact name."
  fi;

  ${TAR} -cf - \
    -C ${tensorflow_dir}/bazel-bin/native_client/ generate_trie${PLATFORM_EXE_SUFFIX} \
    -C ${tensorflow_dir}/bazel-bin/native_client/ libdeepspeech.so \
    -C ${deepspeech_dir}/ LICENSE \
    -C ${deepspeech_dir}/native_client/ deepspeech${PLATFORM_EXE_SUFFIX} \
    -C ${deepspeech_dir}/native_client/kenlm/ README.mozilla \
    | ${XZ} > "${artifacts_dir}/${artifact_name}"
}

package_native_client_ndk()
{
  deepspeech_dir=${DS_DSDIR}
  artifacts_dir=${TASKCLUSTER_ARTIFACTS}
  artifact_name=$1
  arch_abi=$2

  if [ ! -d ${deepspeech_dir} -o ! -d ${artifacts_dir} ]; then
    echo "Missing directory. Please check:"
    echo "deepspeech_dir=${deepspeech_dir}"
    echo "artifacts_dir=${artifacts_dir}"
    exit 1
  fi;

  if [ -z "${artifact_name}" ]; then
    echo "Please specify artifact name."
  fi;

  if [ -z "${arch_abi}" ]; then
    echo "Please specify arch abi."
  fi;

  tar -cf - \
    -C ${deepspeech_dir}/native_client/libs/${arch_abi}/ deepspeech \
    -C ${deepspeech_dir}/native_client/libs/${arch_abi}/ libdeepspeech.so \
    -C ${deepspeech_dir}/native_client/libs/${arch_abi}/ libc++_shared.so \
    -C ${deepspeech_dir}/ LICENSE \
    -C ${deepspeech_dir}/native_client/kenlm/ README.mozilla \
    | pixz -9 > "${artifacts_dir}/${artifact_name}"
}

android_sdk_accept_licenses()
{
  pushd "${ANDROID_SDK_HOME}"
    yes | ./tools/bin/sdkmanager --licenses
  popd
}

android_install_sdk()
{
  if [ -z "${ANDROID_SDK_HOME}" ]; then
    echo "No Android SDK home available, aborting."
    exit 1
  fi;

  mkdir -p "${ANDROID_SDK_HOME}" || true
  wget -P "${TASKCLUSTER_TMP_DIR}" https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip

  pushd "${ANDROID_SDK_HOME}"
    unzip -qq "${TASKCLUSTER_TMP_DIR}/sdk-tools-linux-4333796.zip"
  popd

  android_sdk_accept_licenses
}

android_install_ndk()
{
  if [ -z "${ANDROID_NDK_HOME}" ]; then
    echo "No Android NDK home available, aborting."
    exit 1
  fi;

  wget -P "${TASKCLUSTER_TMP_DIR}" https://dl.google.com/android/repository/android-ndk-r18b-linux-x86_64.zip

  mkdir -p ${DS_ROOT_TASK}/DeepSpeech/Android/
  pushd ${DS_ROOT_TASK}/DeepSpeech/Android/
    unzip -qq "${TASKCLUSTER_TMP_DIR}/android-ndk-r18b-linux-x86_64.zip"
  popd
}

android_setup_emulator()
{
  android_install_sdk

  if [ -z "${ANDROID_SDK_HOME}" ]; then
    echo "No Android SDK home available, aborting."
    exit 1
  fi;

  if [ -z "$1" ]; then
    echo "No ARM flavor, please give one."
    exit 1
  fi;

  flavor=$1
  api_level=${2:-android-25}

  export PATH=${ANDROID_SDK_HOME}/tools/bin/:${ANDROID_SDK_HOME}/platform-tools/:$PATH
  export DS_BINARY_PREFIX="adb shell LD_LIBRARY_PATH=${ANDROID_TMP_DIR}/ds/ ${ANDROID_TMP_DIR}/ds/"

  # minutes (2 minutes by default)
  export ADB_INSTALL_TIMEOUT=8

  # Pipe yes in case of license being shown
  yes | sdkmanager --update
  yes | sdkmanager --install "emulator"

  android_install_sdk_platform "${api_level}"

  # Same, yes in case of license
  yes | sdkmanager --install "system-images;${api_level};google_apis;${flavor}"

  android_sdk_accept_licenses

  avdmanager create avd --name "ds-pixel" --device 17 --package "system-images;${api_level};google_apis;${flavor}"

  # -accel on is needed otherwise it is too slow, but it will require KVM support exposed
  pushd ${ANDROID_SDK_HOME}
    ./tools/emulator -verbose -avd ds-pixel -no-skin -no-audio -no-window -no-boot-anim -accel off &
    emulator_rc=$?
    export ANDROID_DEVICE_EMULATOR=$!
  popd

  if [ "${emulator_rc}" -ne 0 ]; then
    echo "Error starting Android emulator, aborting."
    exit 1
  fi;

  adb wait-for-device

  adb shell id
  adb shell cat /proc/cpuinfo

  adb shell service list
}

android_install_sdk_platform()
{
  api_level=${1:-android-27}

  if [ -z "${ANDROID_SDK_HOME}" ]; then
    echo "No Android SDK home available, aborting."
    exit 1
  fi;

  export PATH=${ANDROID_SDK_HOME}/tools/bin/:${ANDROID_SDK_HOME}/platform-tools/:$PATH

  # Pipe yes in case of license being shown
  yes | sdkmanager --update
  yes | sdkmanager --install "platform-tools"
  yes | sdkmanager --install "platforms;${api_level}"

  android_sdk_accept_licenses
}

android_wait_for_emulator()
{
  while [ "${boot_completed}" != "1" ]; do
    sleep 15
    boot_completed=$(adb shell getprop sys.boot_completed | tr -d '\r')
  done
}

android_setup_ndk_data()
{
  adb shell mkdir ${ANDROID_TMP_DIR}/ds/
  adb push ${TASKCLUSTER_TMP_DIR}/ds/* ${ANDROID_TMP_DIR}/ds/

  adb push \
    ${TASKCLUSTER_TMP_DIR}/${model_name} \
    ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav \
    ${TASKCLUSTER_TMP_DIR}/alphabet.txt \
    ${ANDROID_TMP_DIR}/ds/
}

android_setup_apk_data()
{
  adb shell mkdir ${ANDROID_TMP_DIR}/test/

  adb push \
    ${TASKCLUSTER_TMP_DIR}/${model_name} \
    ${TASKCLUSTER_TMP_DIR}/LDC93S1.wav \
    ${TASKCLUSTER_TMP_DIR}/alphabet.txt \
    ${TASKCLUSTER_TMP_DIR}/lm.binary \
    ${TASKCLUSTER_TMP_DIR}/trie \
    ${ANDROID_TMP_DIR}/test/
}

android_stop_emulator()
{
  if [ -z "${ANDROID_DEVICE_EMULATOR}" ]; then
    echo "No ANDROID_DEVICE_EMULATOR"
    exit 1
  fi;

  # Gracefully stop
  adb shell reboot -p &

  # Just in case, let it 30 seconds before force-killing
  sleep 30
  kill -9 ${ANDROID_DEVICE_EMULATOR} || true
}
