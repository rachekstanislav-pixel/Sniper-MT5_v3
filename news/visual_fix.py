"""Pure rendering patch. No trading function, input or news logic is edited."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def original_namespace(base):
    start=base.index('void InitVisualNamespace() {')
    end=base.index('\nstring ViewName(',start)
    return base[start:end]

def apply(base):
    original=original_namespace(base)
    fixed=(ROOT/'news/visual_namespace.mqpart').read_text()+'\n'
    return base.replace(original,fixed,1)

def revert(output, baseline):
    fixed=(ROOT/'news/visual_namespace.mqpart').read_text()+'\n'
    if output.count(fixed)!=1:
        raise AssertionError('Visual patch missing or duplicated')
    return output.replace(fixed,original_namespace(baseline),1)
