Artix-7 using Symbiflow
-----------------------

This is an out-of-tree use of [symbiflow-arch-defs] to build for an Artix-7
target.

This uses files generated from [symbiflow-arch-defs], so check out and build
it somewhere, then point `SYMBIFLOW_ARCH_DEFS` in this Makefile to it.

Build and send to board with

```
make prog
```

Target here is an Artix-7 Digilent BASYS3 board.

[symbiflow-arch-defs]: https://github.com/SymbiFlow/symbiflow-arch-defs
