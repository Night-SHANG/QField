"""Official TianDiTu Shaanxi source templates.

Tokens are intentionally never stored here. They are supplied when generating a
project and become part of that generated local project only.
"""

SHAANXI_CRS = "EPSG:4490"
MIN_ZOOM = 0
MAX_ZOOM = 18

IMAGERY_XYZ = (
    "https://shaanxi.tianditu.gov.cn/ServiceSystem/Tile/rest/service/"
    "SxImgMap/{token}/TileServer/tile/{z}/{y}/{x}"
)
IMAGERY_LABEL_XYZ = (
    "https://shaanxi.tianditu.gov.cn/ServiceSystem/Tile/rest/service/"
    "SxImgLabelMap/{token}/TileServer/tile/{z}/{y}/{x}"
)

# Official vector map endpoint. This is a Mapbox-style VectorTile style URL,
# not an ordinary XYZ raster source. Kept separately to prevent accidentally
# loading it through the raster provider.
VECTOR_STYLE_URL = (
    "https://shaanxi.tianditu.gov.cn/ServiceSystem/Tile/rest/service/"
    "sxww2022Geo/{token}/VectorTileServer/styles/default.json"
)


def with_token(template: str, token: str) -> str:
    token = token.strip()
    if not token:
        raise ValueError("TianDiTu Shaanxi token must not be empty")
    if any(ch in token for ch in "/?#&"):
        raise ValueError("TianDiTu Shaanxi token contains unsafe URL characters")
    return template.format(token=token, z="{z}", y="{y}", x="{x}")
