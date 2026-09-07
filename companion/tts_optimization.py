"""Reproducible, reversible patch for the pinned v2 attention hot path.

The upstream batch decoder explicitly disables torch SDPA. Preserve its blocked
boolean-mask semantics while replacing materialized attention with PyTorch SDPA.
Applied before importing the TorchScript classes, so compilation sees real source.
"""
from pathlib import Path
import hashlib

START='def scaled_dot_product_attention('
END='\n@torch.jit.script\nclass T2SMLP:'
PATCH='''def scaled_dot_product_attention(query:torch.Tensor, key:torch.Tensor, value:torch.Tensor, attn_mask:Optional[torch.Tensor]=None, scale:Optional[torch.Tensor]=None) -> torch.Tensor:
    # MATE_SDPA_V1: upstream bool True means blocked; SDPA True means allowed.
    mask = attn_mask
    if mask is not None and mask.dtype == torch.bool:
        mask = ~mask
    factor: Optional[float] = None
    if scale is not None:
        factor = float(scale.item())
    return F.scaled_dot_product_attention(query, key, value, attn_mask=mask, dropout_p=0.0, scale=factor)
'''

def apply(root:Path,enabled=True):
    path=root/'GPT_SoVITS/AR/models/t2s_model.py'
    backup=path.with_suffix('.py.mate-original')
    source=path.read_text()
    if not backup.exists():
        if 'MATE_SDPA_V1' in source:raise RuntimeError('Missing pristine attention backup')
        # Refuse patching an unrelated upstream version.
        if hashlib.sha256(source.encode()).hexdigest()!=ORIGINAL_SHA256:
            raise RuntimeError('Unexpected GPT-SoVITS decoder version; reinstall pinned vendor')
        backup.write_text(source)
    original=backup.read_text()
    if hashlib.sha256(original.encode()).hexdigest()!=ORIGINAL_SHA256:raise RuntimeError('Invalid original decoder backup')
    start=original.index(START);end=original.index(END,start)
    patched=original[:start]+PATCH+original[end:]
    if source not in (original,patched):raise RuntimeError('Decoder has unrelated edits; refusing overwrite')
    target=patched if enabled else original
    if source!=target:path.write_text(target)
    return enabled

ORIGINAL_SHA256='f2fe03eb0890743f4d860c254dd08420c9002e28493c4f66e85727db2414df99'
