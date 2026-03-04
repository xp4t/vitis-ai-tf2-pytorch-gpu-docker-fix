#!/bin/bash

set -ex

# ─── Retry helper ────────────────────────────────────────────────────────────
# Usage: retry <max_attempts> <delay_seconds> <command...>
retry() {
    local attempts=$1 delay=$2
    shift 2
    for i in $(seq 1 "$attempts"); do
        "$@" && return 0
        echo "[retry] Attempt $i/$attempts failed. Retrying in ${delay}s..."
        sleep "$delay"
    done
    echo "[retry] All $attempts attempts failed."
    return 1
}
# ─────────────────────────────────────────────────────────────────────────────

# ─── pip_requirements installer ──────────────────────────────────────────────
# Installs packages from pip_requirements.txt one by one, handling the two
# known legacy packages that have conflicting setuptools requirements:
#   - ck>=2.6       needs setuptools>=61 (uses setuptools.command.build)
#   - orderedset    needs setuptools<58  (uses check_test_suite)
# All other packages are installed with the default setuptools version.
install_pip_requirements() {
    local req_file="$1"
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
        # Skip blank lines and comments
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue

        pkg_name=$(echo "$pkg" | sed 's/[>=<!].*//' | tr '[:upper:]' '[:lower:]' | xargs)

        if [[ "$pkg_name" == "ck" ]]; then
            echo "[pip_requirements] Installing $pkg with setuptools>=61..."
            pip install --upgrade "setuptools>=61"
            retry 3 15 pip install "$pkg"
        elif [[ "$pkg_name" == "orderedset" || "$pkg_name" == "protobuf" ]]; then
            echo "[pip_requirements] Installing $pkg with setuptools<58..."
            pip install "setuptools<58"
            retry 3 15 pip install "$pkg"
        else
            retry 3 15 pip install "$pkg"
        fi
    done < "$req_file"
    # Restore a reasonable modern setuptools after legacy installs
    pip install --upgrade "setuptools>=61"
}
# ─────────────────────────────────────────────────────────────────────────────

sudo chmod 777 /scratch
if [[ ${VAI_CONDA_CHANNEL} =~ .*"tar.gz" ]]; then \
       cd /scratch/; \
       retry 3 15 wget -O conda-channel.tar.gz --progress=dot:mega ${VAI_CONDA_CHANNEL}; \
       tar -xzvf conda-channel.tar.gz; \
       export VAI_CONDA_CHANNEL=file:///scratch/conda-channel; \
fi;
sudo mkdir -p $VAI_ROOT/compiler

if [[ ${DOCKER_TYPE} != 'cpu' ]]; then \
    arch_type="_${DOCKER_TYPE}";
else
    arch_type="";
fi

conda_channel="${VAI_CONDA_CHANNEL}"

if [[ ${DOCKER_TYPE} == 'rocm' ]]; then \
    tensorflow_ver="tensorflow-${DOCKER_TYPE}==2.11.1.550  keras==2.11";
else
    tensorflow_ver="tensorflow==2.12 keras==2.12";
fi

if [[ ${DOCKER_TYPE} == 'cpu' ]]; then
   . $VAI_ROOT/conda/etc/profile.d/conda.sh \
    && mkdir -p $VAI_ROOT/conda/pkgs \
    && python3 -m pip install --upgrade pip wheel setuptools \
    && conda config --env --remove-key channels || true \
    && conda config --env --remove channels defaults || true \
    && conda config --env --append channels conda-forge \
    && conda config --env --append channels ${VAI_CONDA_CHANNEL} \
    && cat ~/.condarc \
    && retry 3 30 mamba env create -f /scratch/${DOCKER_TYPE}_conda/vitis-ai-tensorflow2.yml \
    && conda activate vitis-ai-tensorflow2 \
    && retry 3 30 mamba install --no-update-deps vai_q_tensorflow2 pydot pyyaml jupyter ipywidgets \
            dill progressbar2 pytest pandas matplotlib \
             -c ${VAI_CONDA_CHANNEL} -c conda-forge \
        && retry 3 15 pip install pillow \
        && install_pip_requirements /scratch/pip_requirements.txt \
        && retry 3 15 pip install transformers protobuf==3.20.3 pycocotools scikit-learn scikit-image tqdm easydict onnx==1.13.0 numpy==1.22 \
        && retry 3 15 pip install --force-reinstall wrapt==1.14 absl-py astunparse gast google-pasta grpcio jax keras==2.12 libclang opt-einsum tensorboard tensorflow-estimator==2.12 termcolor \
        && pip uninstall -y h5py \
        && pip uninstall -y h5py \
        && retry 3 30 mamba install -y --override-channels --force-reinstall h5py=2.10.0 tensorflow-onnx zendnn-tensorflow2 -c conda-forge \
        && pip install "setuptools<58" \
        && pip install --force-reinstall numpy==1.22 protobuf==3.20.3 \
        && pip install --upgrade "setuptools>=61" \
    && conda config --env --remove-key channels \
    && conda clean -y --force-pkgs-dirs \
    && sudo cp -r $CONDA_PREFIX/lib/python3.8/site-packages/vaic/arch $VAI_ROOT/compiler/arch \
    && rm -fr ~/.cache  \
    && sudo rm -fr /scratch/*
elif [[ ${DOCKER_TYPE} == 'rocm' ]]; then
  . $VAI_ROOT/conda/etc/profile.d/conda.sh \
    && mkdir -p $VAI_ROOT/conda/pkgs \
    && sudo python3 -m pip install --upgrade pip wheel setuptools \
    && conda config --env --remove-key channels || true \
    && conda config --env --remove channels defaults || true \
    && conda config --env --append channels conda-forge \
    && conda config --env --append channels ${conda_channel} \
    && retry 3 30 mamba env create -f /scratch/${DOCKER_TYPE}_conda/vitis-ai-tensorflow2.yml \
    && conda activate vitis-ai-tensorflow2 \
    && mamba install /scratch/conda-channel/linux-64/tensorflow-onnx-3.5.0-hcdf1d9b_18.tar.bz2 \
    && retry 3 30 mamba install --no-update-deps -y pydot pyyaml jupyter ipywidgets \
            dill progressbar2 pytest scikit-learn pandas matplotlib \
            -c ${conda_channel} -c conda-forge \
        && retry 3 15 pip install pillow \
        && install_pip_requirements /scratch/pip_requirements.txt \
        && retry 3 15 pip install pycocotools scikit-image tqdm easydict \
        && retry 3 15 pip install --ignore-installed tensorflow-rocm==2.11.1.550 keras==2.11 \
        && pip install "setuptools<58" \
        && pip install protobuf==3.20.3 \
        && pip install --upgrade "setuptools>=61" \
        && pip uninstall -y h5py \
        && pip uninstall -y h5py \
        && retry 3 30 mamba install -y --override-channels --force-reinstall h5py=2.10.0 -c conda-forge \
    && conda clean -y --force-pkgs-dirs \
    && sudo rm -fr ~/.cache \
    && sudo rm -fr /scratch/* \
    && conda config --env --remove-key channels \
    && conda activate vitis-ai-tensorflow2 \
    && sudo mkdir -p $VAI_ROOT/compiler \
    && sudo cp -r $CONDA_PREFIX/lib/python3.8/site-packages/vaic/arch $VAI_ROOT/compiler/arch
else
  . $VAI_ROOT/conda/etc/profile.d/conda.sh \
    && mkdir -p $VAI_ROOT/conda/pkgs \
    && sudo python3 -m pip install --upgrade pip wheel setuptools \
    && conda config --env --remove-key channels || true \
    && conda config --env --remove channels defaults || true \
    && conda config --env --append channels conda-forge \
    && conda config --env --append channels ${VAI_CONDA_CHANNEL} \
    && retry 3 30 mamba env create -f /scratch/${DOCKER_TYPE}_conda/vitis-ai-tensorflow2.yml \
    && conda activate vitis-ai-tensorflow2 \
    && retry 3 15 pip install --ignore-installed ${tensorflow_ver} \
    && retry 3 30 mamba install --no-update-deps -y pydot pyyaml jupyter ipywidgets \
            dill progressbar2 pytest pandas matplotlib \
            -c ${conda_channel} -c conda-forge \
        && retry 3 15 pip install pillow \
        && install_pip_requirements /scratch/pip_requirements.txt \
        && retry 3 15 pip install transformers pycocotools scikit-learn scikit-image tqdm easydict \
        && retry 3 15 pip install --ignore-installed ${tensorflow_ver} \
        && pip uninstall -y h5py \
        && pip uninstall -y h5py \
        && retry 3 30 mamba install -y --override-channels --force-reinstall h5py=2.10.0 -c conda-forge \
    && pip install "setuptools<58" \
    && pip install protobuf==3.20.3 \
    && pip install --upgrade "setuptools>=61" \
    && conda clean -y --force-pkgs-dirs \
    && sudo rm -fr ~/.cache \
    && sudo rm -fr /scratch/* \
    && conda config --env --remove-key channels \
    && conda activate vitis-ai-tensorflow2 \
    && sudo mkdir -p $VAI_ROOT/compiler \
    && sudo cp -r $CONDA_PREFIX/lib/python3.8/site-packages/vaic/arch $VAI_ROOT/compiler/arch
fi
