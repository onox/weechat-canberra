[![License](https://img.shields.io/github/license/onox/weechat-canberra.svg?color=blue)](https://github.com/onox/weechat-canberra/blob/master/LICENSE)
[![GitHub release](https://img.shields.io/github/release/onox/weechat-canberra.svg)](https://github.com/onox/weechat-canberra/releases/latest)
[![IRC](https://img.shields.io/badge/IRC-%23ada%20on%20freenode-orange.svg)](https://webchat.freenode.net/?channels=ada)

# weechat-canberra

A [WeeChat][url-weechat] plug-in written in Ada 2012 that plays sounds
using Canberra when a message is received, your nick name is highlighted,
or when the client has (dis)connected to the IRC server.

If you are away (after 30 minutes of inactivity) then you will hear
the sound of an incoming phone call if a message is received between
07:00 and 21:00, otherwise the plug-in tells the sender that you will
be woken up around 07:00.

## Dependencies

In order to build the plug-in, you need to have:

 * An Ada 2012 compiler

 * GPRBuild and `make`

 * [weechat-ada][url-weechat-ada]

## Installing dependencies on Ubuntu 18.04 LTS

Build and install [weechat-ada][url-weechat-ada].

## Installation

A Makefile is provided to build the source code. Use `make` to build
the source code:

```
$ make
```

Install the `gcc` package if you get a message about
"plugin needed to handle lto object":

```sh
$ sudo apt install gcc
```

You can override CFLAGS if desired. After having compiled the source code,
the plug-in can be installed to `~/.weechat/plugins/` by executing:

```
$ make install
```

## Contributing

Read the [contributing guidelines][url-contributing] if you want to add
a bugfix or an improvement.

## License

This plug-in is licensed under the [Apache License 2.0][url-apache].
The first line of each Ada file should contain an SPDX license identifier tag that
refers to this license:

    SPDX-License-Identifier: Apache-2.0

  [url-apache]: https://opensource.org/licenses/Apache-2.0
  [url-contributing]: /CONTRIBUTING.md
  [url-weechat]: https://weechat.org/
  [url-weechat-ada]: https://github.com/onox/weechat-ada
