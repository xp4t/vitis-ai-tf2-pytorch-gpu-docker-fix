# Vitis AI TensorFlow 2/PyTorch GPU Docker Build Fix

This repository provides a verified fix for the **403 Forbidden error** and subsequent **multi-download failure** during the TensorFlow 2 Docker image build in **Vitis AI GPU environments**.

---

## Background

When building the TensorFlow 2 Docker image in Vitis AI, the process frequently fails during Conda environment setup with the following error:

```
RuntimeError: Multi-download failed.
Unable to retrieve repodata (response: 403) for https://repo.anaconda.com/pkgs/main/linux-64/repodata.json
```

This occurs because the default **Anaconda `repo.anaconda.com`** channels have restricted access. The Docker build tries to pull packages from these blocked URLs, causing the entire build to fail.

---

## Key Changes Made

| Location                 | Lines | Description                                                                           |
| ------------------------ | ----- | ------------------------------------------------------------------------------------- |
| **CPU path**             | 29–31 | Removed the default channel and explicitly added `conda-forge` before the VAI channel |
| **ROCm path**            | 56–59 | Removed the default channel and explicitly added `conda-forge`                        |
| **ROCm install command** | 62    | Removed `-c defaults` from the `mamba install` command                                |
| **GPU path (else)**      | 78–81 | Removed default channel and explicitly added `conda-forge`                            |
| **GPU install command**  | 85    | Removed `-c defaults` from the `mamba install` command                                |

These edits completely remove references to the restricted **Anaconda main and R** repositories, relying instead on **conda-forge** and your **local channel**.

---

## Root Cause

The issue originated from lines in the build process such as:

```bash
mamba install --no-update-deps -y pydot pyyaml jupyter ipywidgets dill progressbar2 pytest pandas matplotlib pillow -c file:///scratch/conda-channel -c conda-forge -c defaults
```

The inclusion of `-c defaults` forces `mamba` to contact Anaconda’s servers (`repo.anaconda.com`), which are often restricted. This leads to the **403 Forbidden** response and `Multi-download failed` error.

---

## Fixed Version Example

After the fix, all `mamba` commands should look like this:

```bash
mamba install --no-update-deps -y pydot pyyaml jupyter ipywidgets dill progressbar2 pytest pandas matplotlib pillow \
    -c file:///scratch/conda-channel -c conda-forge
```

This ensures that the build process:

* Uses only `conda-forge` and local channels.
* Avoids any contact with `repo.anaconda.com`.
* Works for CPU, ROCm, and CUDA-based TensorFlow 2 images.

---

## Example Build Error (Before Fix)

```
1049.4 RuntimeError: Multi-download failed.
Unable to retrieve repodata (response: 403) for https://repo.anaconda.com/pkgs/main/linux-64/repodata.json
...
ERROR: failed to solve: process "/bin/bash -c if [[ -n \"${TARGET_FRAMEWORK}\" ]]; then  bash ./install_${TARGET_FRAMEWORK}.sh; fi" did not complete successfully: exit code: 1
```

After applying the fix, the error no longer occurs, and the Docker image builds successfully.

---

## Usage

Clone and build the fixed image:

```bash
git clone https://github.com/xp4t/vitis-ai-tf2-pytorch-gpu-docker-fix.git
cd vitis-ai-tf2-pytorch-gpu-docker-fix
mv install_tf2.sh install_torch.sh ~/Vitis-AI/docker/common
cd ~/Vitis-AI/docker/common
chmod +x install_torch.sh
chmod +x install_tf2.sh
cd ..
./docker_build.sh -t gpu -f pytorch
```
OR
```bash
./docker_build.sh -t gpu -f tf2 
```

Verify it with

```bash
docker images
```
Expect an Output of

```bash
REPOSITORY                        TAG                       IMAGE ID       CREATED         SIZE
xilinx/vitis-ai-tensorflow2-gpu   3.5.0.001-7a0d5a695       68ca758ec2e3   5 days ago      15.2GB
xiinx/vitis-ai-gpu-tf2-base       latest                    a0779f677dae   6 days ago      7.48GB
xilinx/vitis-ai-pytorch-gpu       3.5.0.001-7a0d5a695       f77d90366077   6 days ago      31.9GB
xiinx/vitis-ai-gpu-pytorch-base   latest                    2db5d9706e78   6 days ago      11.2GB
hello-world                       latest                    1b44b5a3e06a   2 months ago    10.1kB
nvidia/cuda                       11.7.1-base-ubuntu20.04   c6ceebac4227   23 months ago   211MB
xilinx/vitis-ai-pytorch-cpu       latest                    10667a5b7322   2 years ago     11.7GB
```
Run it with GPU support:

```bash
cd ..
./docker_run.sh xilinx/vitis-ai-pytorch-gpu:3.5.0.001-7a0d5a695 
```
OR
```bash
./docker_run.sh xilinx/vitis-ai-tensorflow2-gpu:3.5.0.001-7a0d5a695 
```
## Changes to `install_tf2.sh`

### 1. Added `retry()` helper function
All network-dependent commands (`wget`, `mamba env create`, `mamba install`, `pip install`) are now wrapped with `retry 3 <delay>` — 3 attempts with a delay between each. This handles intermittent network timeouts during the Docker build.

### 2. Added `install_pip_requirements()` helper function
Replaces the single `pip install -r /scratch/pip_requirements.txt` call. The problem is that packages in `pip_requirements.txt` have **conflicting `setuptools` version requirements** — they can't all be installed together:

| Package | Needs | Reason |
|---|---|---|
| `ck >= 2.6` | `setuptools >= 61` | Uses `setuptools.command.build` (new API) |
| `orderedset` | `setuptools < 58` | Uses `check_test_suite` (removed in 58) |
| `protobuf == 3.20.3` | `setuptools < 58` | Uses `check_test_suite` (removed in 58) |

The function reads the requirements file line by line and temporarily pins setuptools to the right version for each problematic package, then restores `setuptools>=61` at the end.

### 3. Fixed standalone `protobuf==3.20.3` installs (all 3 branches)
The original script used `pip install --force --no-binary protobuf protobuf==3.20.3` which forces a **source build**, triggering the `check_test_suite` error. Replaced in all three branches (`cpu`, `rocm`, `gpu`) with:
```bash
pip install "setuptools<58"
pip install protobuf==3.20.3      # now uses pre-built wheel
pip install --upgrade "setuptools>=61"
```

### 4. Removed all `"setuptools<58"` global pins
The previous fix attempt globally pinned `setuptools<58` before every `pip install -r` call, which solved `orderedset` but broke `ck`. These global pins are gone — setuptools version is now managed per-package inside `install_pip_requirements()`.

---

**In short:** the core problem was that three legacy packages in the requirements have mutually incompatible `setuptools` needs. The solution is to temporarily swap the setuptools version for each offending package rather than trying to pin one global version.

## Summary

* Removed all access to `repo.anaconda.com`.
* Added `conda-forge` and local channel explicitly.
* Works across CPU, ROCm, and GPU builds.
* Verified fix for PyTorch path on Vitis AI.

---

## License

MIT License — feel free to use, modify, and contribute.

---

## Contributing

Pull requests are welcome! If you encounter similar build issues in PyTorch or other Vitis AI Docker variants, feel free to open an issue or contribute to extending this fix.
