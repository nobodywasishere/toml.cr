# Main entry point for TOML parsing.
module TOML
  # A TOML Table. Just a convenience alias.
  alias Table = Hash(String, TOML::Any)

  # Parses a string.
  def self.parse(input : String) : TOML::Table
    Parser.parse(IO::Memory.new(input))
  end

  # Parses from an `IO`
  def self.parse(io : IO) : TOML::Table
    Parser.parse(io)
  end

  # Parses a file.
  def self.parse_file(filename : String | Path) : TOML::Table
    parse File.read(filename)
  end

  # Builds a TOML 1.1 document and returns it as a string.
  def self.build(& : Builder ->) : String
    builder = Builder.new
    yield builder
    builder.to_toml
  end

  # Builds a TOML 1.1 document and writes it to the given IO.
  def self.build(io : IO, & : Builder ->) : Nil
    builder = Builder.new
    yield builder
    builder.to_toml(io)
  end

  # Serializes a table as a TOML 1.1 document. Nested tables use inline syntax.
  #
  # Values may be TOML::Any or Crystal booleans, integers, floats, strings, date
  # and time values, arrays, and hashes with String keys.
  def self.dump(table : Hash(String, V)) : String forall V
    String.build { |io| dump(table, io) }
  end

  # Writes a TOML 1.1 document to the given IO.
  def self.dump(table : Hash(String, V), io : IO) : Nil forall V
    Writer.new(io).write(table)
  end
end

require "./toml/temporal"
require "./toml/*"
