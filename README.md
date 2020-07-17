# ICrystal

ICrystal is a crystal kernel for [Jupyter project](https://jupyter.org/try).

Current status: early development stages (the kernel is very minimal). Expect more features in the future.

It is ported from the [IRuby](https://github.com/SciRuby/iruby) kernel.

![icrystal](https://user-images.githubusercontent.com/470056/81830095-f25cd280-953b-11ea-9922-0f6477399cef.gif)

## Installation

Prerequisites

- The latest version of crystal.
- LLVM development files.
- [Jupyter](https://jupyter.org/)
- [ZeroMQ](https://zeromq.org/)

Clone the repository and switch current directory:

```
git clone https://github.com/RomainFranceschini/icrystal.git
cd icrystal
```

Install dependencies

```
shards install
```

Build icrystal

```
shards build
```

## Usage

To register the kernel (ensure jupyter is installed):

```
bin/icrystal register
```

Now run jupyter and choose the ICrystal kernel as a backend for your notebook:

```
jupyter notebook
```

or

```
jupyter lab
```

## How it works

The code submitted to the kernel is compiled using parts of the [icr](https://github.com/crystal-community/icr) shard.

## Development

To run the jupyter kernel testing tool (Python 3.4 or greater required):

```
pip3 install jupyter_kernel_test
python3 test/test_kernel.py
```

## Roadmap

- [ ] Widget support
- [ ] Rich output (images, ...) support
- [ ] Add special commands
- [ ] Support adding/removing shards dependencies
- [ ] Write specs

## Contributing

1. Fork it (<https://github.com/RomainFranceschini/icrystal/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Romain Franceschini](https://github.com/RomainFranceschini) - creator and maintainer

## License

Copyright (c) ICrystal contributors.

Licensed under the [MIT](LICENSE) license.
