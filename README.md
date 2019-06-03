
**cpptools** is a very small set of tools that deal with C and C++ code. It's mostly useful to dig through automatically generated code.

includes:

  + rmcpp: removes C and C++ comments from source files, can remove preprocessor as well, and a bunch of other things.

  + cpp2ast: uses `clang` to produce the AST representation of a source file. This is really just a wrapper around 1. preprocessing the file, 2. invoking the cc1 backend. that's it.


