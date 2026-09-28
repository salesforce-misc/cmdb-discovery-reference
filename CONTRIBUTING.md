# Contributing Guide For CMDB Discovery Reference

This page lists the operational governance model of this project, as well as the
recommendations and requirements for how to best contribute to the CMDB Discovery
Reference package. We strive to obey these as best as possible. As always, thanks
for contributing – we hope these guidelines make it easier and shed some light on
our approach and processes.

# Governance Model

## Published but not supported

This project is published as a **reference sample**: it exists so that partners and
developers building a CMDB discovery integration can clone it, rename the `Sample*`
pieces, and fill in their own product's logic. It contains useful patterns and
scaffolding we wish to share with the wider community. Although occasional work may
be done on it, we are not actively soliciting feature contributions, and it is
released under the [Apache License 2.0](LICENSE.txt) so you are free to copy and
adapt it, subject to the license terms.

# Issues, requests & ideas

Use the GitHub Issues page to submit issues, enhancement requests, and to discuss ideas.

### Bug Reports and Fixes

- If you find a bug, please search for it in the Issues, and if it isn't already
  tracked, create a new issue. Fill out the "Bug Report" section of the issue
  template. Even if an Issue is closed, feel free to comment and add details — it
  will still be reviewed.
- Issues that have already been identified as a bug (note: able to reproduce) will
  be labelled `bug`.
- If you'd like to submit a fix for a bug, send a Pull Request and mention the Issue
  number. Include tests that isolate the bug and verify that it was fixed.

### New Features

- If you'd like to add new functionality, describe the problem you want to solve in
  a new Issue.
- Issues identified as a feature request will be labelled `enhancement`.
- Because this is a reference sample rather than a maintained product, please wait
  for feedback from the maintainers before spending significant time on code — an
  `enhancement` may not align with keeping the sample small and easy to follow.

### Tests, Documentation, Miscellaneous

- Improvements to tests, documentation, or clarity of the sample are always welcome.
  For trivial changes, go ahead and send a Pull Request. For anything larger, open
  an Issue to discuss first.

# Contribution Checklist

- [x] Clean, simple, well styled code
- [x] Commits should be atomic and messages must be descriptive. Related issues
      should be mentioned by Issue number.
- [x] Comments — module-level & function-level comments; comments on complex blocks.
- [x] Tests — the test suite must be complete and pass; increase code coverage.
- [x] Dependencies — minimize the number of dependencies.
- [x] Reviews — changes must be approved via peer code review.

# Creating a Pull Request

1. **Ensure the bug/feature was not already reported** by searching on GitHub under
   Issues. If none exists, create a new issue so others can track what you are
   adding/fixing.
2. **Fork** and **clone** the repo to your machine.
3. **Create** a new branch to contain your work (e.g. `git checkout -b fix-issue-11`).
4. **Commit** changes to your own branch.
5. **Push** your work back up to your fork.
6. **Submit** a Pull Request against the `main` branch and refer to the issue(s) you
   are fixing. Keep it simple and small.
7. **Sign** the Salesforce CLA (you will be prompted to do so when submitting the
   Pull Request).

> **NOTE**: Be sure to [sync your fork](https://help.github.com/articles/syncing-a-fork/)
> before making a pull request.

# Contributor License Agreement ("CLA")

In order to accept your pull request, we need you to submit a CLA. You only need to
do this once to work on any of Salesforce's open source projects.

Complete your CLA here: <https://cla.salesforce.com/sign-cla>

# Code of Conduct

Please follow our [Code of Conduct](CODE_OF_CONDUCT.md).

# License

This project is licensed under the [Apache License 2.0](LICENSE.txt). By contributing
your code, you agree to license your contribution under the same terms and to sign the
[Salesforce CLA](https://cla.salesforce.com/sign-cla).
