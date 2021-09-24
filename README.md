# The Acton programming language
[![Test](https://github.com/actonlang/acton/actions/workflows/test.yml/badge.svg)](https://github.com/actonlang/acton/actions/workflows/test.yml)

Acton is a general purpose programming language, designed to be useful for a
wide range of applications, from desktop applications to embedded and
distributed systems. In a first approximation Acton can be described as a
seamless addition of a powerful new construct to an existing language: Acton
adds *actors* to *Python*.

Acton is a compiled language, offering the speed of C but with a considerably
simpler programming model. There is no explicit memory management, instead
relying on garbage collection.

Acton is statically typed with an expressive type language and type inference.
Type inferrence means you don't have to explicitly declare types of every
variable but that the compiler will *infer* the type and performs its checks
accordingly. We can have the benefits of type safety without the extra overhead
involved in declaring types.

The Acton Run Time System (RTS) offers a distributed mode of operation allowing
multiple computers to participate in running one logical Acton system. Actors
can migrate between compute nodes for load sharing purposes and similar. The RTS
offers exactly once delivery guarantees. Through checkpointing of actor states
to a distributed database, the failure of individual compute nodes can be
recovered by restoring actor state. Your system can run forever!

NOTE: Acton is in an experimental phase and although much of the syntax has been
worked out, there may be changes.

NOTE: The RTS currently does not have a garbage collector, severely limiting it
for long running tasks. However, for smaller shorter lived processes, it can
work fairly well.


# Getting started with Acton

## Install acton

### Mac OS X using Homebrew
Acton is available as a Homebrew tap, which can be installed with:
```
brew install actonlang/acton/acton
```

### By downloading a tar ball

Acton is published as GitHub Releases. Download a tar ball from [the Release
page](https://github.com/actonlang/acton/releases). Pick the latest stable
versioned release.

In case you are looking to live on the bleeding edge or have been asked by a
developer (in case you ran into a bug) you can pick `tip`, which is built
directly from the `main` branch.

Extract the Acton tar ball:
```
$ tar jxvf acton-*
```

You will want to include the `acton/bin` directory in your `PATH` so you can use
`actonc`.

`actonc` has run time dependencies and you will need to install the necessary
dependencies for your platform.

#### Debian
```
apt install gcc libprotobuf-c-dev libutf8proc-dev
```

#### Mac OS X
```
brew install protobuf-c util-linux
```

## Compiling an Acton program

Make your own module by creating a directory

```sh
$ mkdir foo
$ cd foo
```

Tell Acton its a module
```sh
$ touch .acton
```

Edit the program source file, let's call it `helloworld.act`, and enter the
following code:

``` Acton
actor main(env):
    print("Hello, world!")
    await async env.exit(0)
```

Compile the program and run it:

```
$ actonc --root main helloworld.act
$ ./helloworld
Hello, world!
```

## Running Acton programs
The final program produced by the Acton compiler is a self contained binary.
Thus it has no run time dependencies. The `helloworld` binary built in the
above example can be shipped to another machine, that does not have `actonc` or
any of its dependencies installed, and still run. Like any other binary, it is
naturally OS and arch dependent though.

## And then...?
Go read the [tutorial!](docs/tutorial/index.html)

# Building Acton from source
See [building Acton from source](docs/building-acton-from-source.md).