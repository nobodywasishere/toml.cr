# toml.cr

[![CI](https://github.com/crystal-community/toml.cr/actions/workflows/ci.yml/badge.svg)](https://github.com/crystal-community/toml.cr/actions/workflows/ci.yml)

A [TOML](https://github.com/toml-lang/toml) parser and writer for [Crystal](http://crystal-lang.org/), supporting [TOML 1.1](https://toml.io/en/v1.1.0).

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  toml:
    github: crystal-community/toml.cr
    branch: master
```

### Usage

```crystal
require "toml"

toml_string = %(
  title = "TOML Example"

  [owner]
  name = "Lance Uppercut"
  dob = 1979-05-27T07:32:00Z
)

toml = TOML.parse(toml_string)
puts toml["title"] #=> "TOML Example"

owner = toml["owner"].as_h
puts owner["name"] #=> "Lance Uppercut"
puts owner["dob"]  #=> "1979-05-27 07:32:00 UTC"
```

Offset date-times are returned as Crystal `Time` values. Local dates, times,
and date-times are returned as `TOML::LocalDate`, `TOML::LocalTime`, and
`TOML::LocalDateTime`. These values expose their calendar or clock components
without using the system time zone or the current date. Use `TOML::Any#raw`
to access them.

Offset date-times use the UTC range of Crystal's time type (years 1 through
9999). Leap seconds are unsupported.

### Writing TOML

```crystal
TOML.dump({"title" => "TOML Example"}) # => "title = \"TOML Example\"\n"
TOML.dump(toml, STDOUT)
```

`TOML.dump` accepts a parsed table or a Crystal hash with string keys.
Supported values include booleans, signed 64-bit integers, floats, strings,
the four date and time types, arrays, and nested hashes with string keys.
Nested tables use inline syntax, and offset date-times are written in UTC.
Dumping a parsed document preserves the values and discards comments and
original formatting.

### Mapping TOML to Crystal types

Include `TOML::Serializable` in a class or struct to map its instance
variables to TOML keys.

```crystal
require "toml"

struct Server
  include TOML::Serializable

  @[TOML::Field(key: "listen-port")]
  getter port : UInt16
  getter host : String = "localhost"
  getter tags : Array(String) = [] of String
end

server = Server.from_toml("listen-port = 8080")
server.port # => 8080
server.to_toml
```

The module supports TOML scalars and temporal types, enums (by member name),
URI values (as strings), arrays, hashes with string or enum keys, unions,
and nested serializable types.
`from_toml` accepts a string, an IO, or a parsed TOML table. `to_toml`
returns a string or writes to an IO, and `to_toml_table` returns a table.
Enum fields and enum table keys accept declared names and unambiguous
snake_case aliases. Writers emit the declared names. Flag combinations use
names joined by ` | `. Floating-point fields also accept integer literals.
These rules apply inside arrays and hashes. Union decoding first tries to
match without integer widening or enum aliases, so `Int64 | Float64`
preserves the type of a numeric literal. Two keys mapping to the same member raise a decoding error.
Reading a union raises `TOML::SerializableError` if more than one member
accepts the value at the same priority. Use a field converter to define an unambiguous format
for overlapping types. A field that holds a subclass of its declared type
also needs a converter if the subclass is to round-trip. Writing raises
`TOML::SerializableError` when the default decoder would lose the subclass
data, including extra state on array and hash subclasses. A typed getter such as
`getter pet : Cat | Dog | String` preserves sibling alternatives even when
Crystal infers their common parent for the instance variable. If the field
exposes only the base class, use a converter to select a subclass.

Missing fields keep their defaults or become nil when nilable. Other
missing fields and type mismatches raise `TOML::SerializableError`.
TOML has no null value. Writing omits nil fields with no initializer or a
literal nil initializer. For other initializers, writing nil raises
`TOML::SerializableError` because omission can restore a default on read.
Writing also raises if two emitted fields share a key. Two readable fields
with the same key cause a compile-time error when compiling the decoder.
Unknown keys are ignored by default. Include `TOML::Serializable::Strict`
to reject them. Strict mode recognizes declared output-only keys and skips
their input values. Use `TOML::Field` for aliases, ignored fields, and custom
converters. Union selection can try converters for several candidates.
Keep converters free of side effects and raise `TOML::SerializableError`
to report invalid input. Generated initialization hooks run after union selection. Custom reader
constructors and converters can run while trying candidates.

### Custom wire formats

A type can implement `initialize(reader : TOML::PullParser)` and
`to_toml(builder : TOML::Builder)`. Generated models use these methods for
nested values too. The reader traverses a parsed TOML tree. Inside
`read_object` or `read_array`, consume each child exactly once with
`read(Type)`, a scalar reader such as `read_string`, or `skip`.

Field converters use the same reader and writer. For example, this converter
stores a percentage as a fraction in Crystal.

```crystal
module Percentage
  def self.from_toml(reader : TOML::PullParser) : Float64
    reader.read_float / 100
  end

  def self.to_toml(value : Float64, builder : TOML::Builder) : Nil
    builder.scalar(value * 100)
  end
end

struct Opacity
  include TOML::Serializable

  @[TOML::Field(converter: Percentage)]
  getter alpha : Float64
end

Opacity.from_toml("alpha = 50").alpha # => 0.5
```

For a model whose table keys come from the input, annotate the model with
`@[TOML::Serializable::Options(converter: MyMapping)]`. The converter
implements `self.from_toml(table : TOML::Table)` returning the model and
`self.to_toml(model)` returning a `TOML::Table`. It controls construction,
unknown-key handling and output for that model, including inside collections.
For a one-way mapping, include `TOML::Serializable::ReadOnly` and implement
only the input method. Writing the model raises `TOML::SerializableError`.

When a type also implements JSON serialization, declare its TOML field
aliases and unit conversions with `TOML::Field`. Put shared derived-state
initialization in `after_initialize` for generated constructors, or call
the model's constructor from a whole-table converter.
