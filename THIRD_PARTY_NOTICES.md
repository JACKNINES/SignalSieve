# Third-party notices

Signal Sieve does not vendor the following source trees in this repository.
`bootstrap-pdf-tools.sh` fetches their pinned revisions into the ignored local
`.build/vendor` directory and builds static components used by the PDF metadata
sanitizer.

## qpdf

- Project: <https://github.com/qpdf/qpdf>
- Pinned revision: `babad179ce5db9a21635c8d1ac17baa59637eada`
- License: Apache License 2.0
- The packaged application copies qpdf's `LICENSE.txt` and `NOTICE.md` from the
  fetched revision into its resources.

## libjpeg-turbo

- Project: <https://github.com/libjpeg-turbo/libjpeg-turbo>
- Pinned revision: `c85e6b905bf237038faa936dab160ebfc5da0344`
- Licenses: IJG, modified BSD, and zlib licenses as documented by the project.
- The packaged application copies the fetched revision's `LICENSE.md` into its
  resources.

These notices are informational and do not replace the complete license texts
shipped with the built application.

## Optional external community service

Signal Sieve contains an adapter for a user-installed local instance of
[`guillaumemeyer/watermarks-remover`](https://github.com/guillaumemeyer/watermarks-remover).
No source code, container image, model, or executable from that project is
vendored or distributed here. The external project and each optional upstream
harness retain their own licenses and notices. Consult the exact revision or
container tag you install; the adapter does not replace those terms.
