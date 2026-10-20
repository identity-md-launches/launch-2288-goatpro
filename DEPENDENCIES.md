# Vendored dependencies

These sources are ordinary repository files, not git submodules. Build and test
require no network access once Foundry and the pinned compiler are available.
Files are copied without source modifications and retain their upstream licenses.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol`, and `LICENSE` | MIT |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | `src/` and both upstream license files | MIT / Apache-2.0 |

OpenZeppelin is the production dependency; forge-std is used only by tests.
Some OpenZeppelin file headers identify `v5.0.0`, their last modification
version within the `v5.0.2` release.

Downloaded release archive SHA-256 checksums:

```text
18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a  openzeppelin-contracts v5.0.2
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94  forge-std v1.9.7
```

Upstream archives:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2`
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`
