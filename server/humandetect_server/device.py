"""Picks where PyTorch models run: Apple GPU (MPS), CUDA, or CPU."""

import os

import torch


def torch_device() -> torch.device:
    forced = os.environ.get("HUMANDETECT_DEVICE")
    if forced:
        return torch.device(forced)
    if torch.cuda.is_available():
        return torch.device("cuda")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")
