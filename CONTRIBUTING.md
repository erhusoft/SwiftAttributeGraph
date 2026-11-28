# Contributing

Thanks for your interest in SwiftAttributeGraph.

## License of contributions

This project is licensed under the [Apache License 2.0](LICENSE). By submitting a pull request you agree that your
contribution is licensed under the same terms, as stated in section 5 of the license.

## Developer Certificate of Origin (DCO)

Every commit must carry a `Signed-off-by` line, which certifies that you wrote the change or have the right to submit it
under this project's license (the text of the [DCO 1.1](https://developercertificate.org/)). Add it with:

```bash
git commit -s -m "area: short description"
```

The line looks like `Signed-off-by: Your Name <you@example.com>` and must use your real name.

## Attribution

Keep the copyright notices and the [NOTICE](NOTICE) file when you redistribute this code, and mark the files you changed, as
the license requires. Do not copy code from Apple's frameworks or from decompiled binaries into a contribution: behaviour is
established by observation against the native framework, and the implementation is written independently.

## Before opening a pull request

- Write or update the tests first and make sure the whole suite passes in debug and release:
  `swift test` and `swift test -c release -Xswiftc -enable-testing`.
- Source code, identifiers, `///` documentation comments and commit messages are in English.
- Do not claim parity with the native framework without a scenario that measured it; see [COVERAGE.md](COVERAGE.md).
