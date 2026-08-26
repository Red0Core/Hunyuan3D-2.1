# Modified by official-imvoiid (Hunyuan3D-2.1 Windows / 16GB VRAM fork).
# Changes: u2net path pinned to the repo folder via U2NET_HOME.

# Hunyuan 3D is licensed under the TENCENT HUNYUAN NON-COMMERCIAL LICENSE AGREEMENT
# except for the third-party components listed below.
# Hunyuan 3D does not impose any additional limitations beyond what is outlined
# in the repsective licenses of these third-party components.
# Users must comply with all terms and conditions of original licenses of these third-party
# components and must ensure that the usage of the third party components adheres to
# all relevant laws and regulations.

# For avoidance of doubts, Hunyuan 3D means the large language models and
# their software and algorithms, including trained model weights, parameters (including
# optimizer states), machine-learning model code, inference-enabling code, training-enabling code,
# fine-tuning enabling code and other elements of the foregoing made publicly available
# by Tencent in accordance with TENCENT HUNYUAN COMMUNITY LICENSE AGREEMENT.

import os

from PIL import Image
from rembg import remove, new_session

# Keep u2net.onnx inside the repo so it travels with the folder. rembg resolves
# both the "already downloaded?" check and the download target from U2NET_HOME,
# so this pins them to the same place. setdefault: an explicit U2NET_HOME still wins.
_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
os.environ.setdefault("U2NET_HOME", os.path.join(_REPO_ROOT, "u2net"))


class BackgroundRemover():
    def __init__(self):
        self.session = new_session()

    def __call__(self, image: Image.Image):
        output = remove(image, session=self.session, bgcolor=[255, 255, 255, 0])
        return output
