[![Build Status](https://travis-ci.org/rock-core/autoproj-overrides-generator.svg?branch=master)](https://travis-ci.org/rock-core/autoproj-overrides-generator)

# Autoproj::OverridesGenerator


## Installation

Run

```console
$ autoproj plugin install --git https://github.com/rock-core/autoproj-overrides-generator
```

## Usage

Run

```console
$ autoproj overrides "https://github.com/rock-core/autoproj-overrides-generator/pull/1"
```

from within an Autoproj workspace and a `autoproj/overrides.d/999-overrides_generator.yml`
file will be generated with what's required to use/test the given Pull Request.

## Development

Install the plugin with a `--path` option to use your working checkout

```console
$ autoproj plugin install autoproj-overrides-generator --path /path/to/checkout
```

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/rock-core/autoproj-overrides-generator. This project is intended to be a
safe, welcoming space for collaboration, and contributors are expected to
adhere to the [Contributor Covenant](http://contributor-covenant.org) code of
conduct.

## License

The gem is available as open source under the terms of the [BSD 3-Clause
License](https://opensource.org/licenses/BSD-3-Clause).

## Code of Conduct

Everyone interacting in the Autoproj::OverridesGenerator project’s codebases, issue trackers,
chat rooms and mailing lists is expected to follow the [code of
conduct](https://github.com/rock-core/autoproj-overrides-generator/blob/master/CODE_OF_CONDUCT.md).
