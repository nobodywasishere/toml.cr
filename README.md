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
arrays, string-keyed hashes, unions, and nested serializable types.
`from_toml` accepts a string, an IO, or a parsed TOML table. `to_toml`
returns a string or writes to an IO, and `to_toml_table` returns a table.
Enum names are case-sensitive. Flag combinations use names joined by ` | `.
Reading a union raises `TOML::SerializableError` if more than one member
accepts the value. Use a field converter to define an unambiguous format
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
to report invalid input. Model initialization hooks run only after a
candidate has been selected.
