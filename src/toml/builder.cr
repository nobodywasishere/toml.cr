# Builds a TOML document from named fields and nested collections.
#
# Use `TOML.build` to write the completed document to a string or an IO.
class TOML::Builder
  @table = TOML::Table.new
  @encoder = TOML::Serializable::Encoder.new

  # Adds a value under *key*. The key is literal, even if it contains dots.
  # Raises `ArgumentError` if the key is already present in this table.
  def field(key : String, value : T) : Nil forall T
    raise ArgumentError.new("Duplicate TOML key #{key.inspect}") if @table.has_key?(key)
    @table[key] = @encoder.write(value)
  end

  # Adds a nested table built by the block.
  def table(key : String, & : Builder ->) : Nil
    child = Builder.new
    yield child
    field(key, TOML::Any.new(child.to_toml_table))
  end

  # Adds an array built by the block.
  def array(key : String, & : ArrayBuilder ->) : Nil
    child = ArrayBuilder.new
    yield child
    field(key, TOML::Any.new(child.to_a))
  end

  # Returns a shallow copy of the document table.
  def to_toml_table : TOML::Table
    @table.dup
  end

  # Renders the current document as TOML.
  def to_toml : String
    TOML.dump(@table)
  end

  # Writes the current document to *io*.
  def to_toml(io : IO) : Nil
    TOML.dump(@table, io)
  end

  # Builds the sequence of values in a TOML array.
  class ArrayBuilder
    @values = Array(TOML::Any).new
    @encoder = TOML::Serializable::Encoder.new

    # Appends a value to the array.
    def value(value : T) : Nil forall T
      @values << @encoder.write(value)
    end

    # Appends a table built by the block.
    def table(& : Builder ->) : Nil
      child = Builder.new
      yield child
      value(TOML::Any.new(child.to_toml_table))
    end

    # Appends an array built by the block.
    def array(& : ArrayBuilder ->) : Nil
      child = ArrayBuilder.new
      yield child
      value(TOML::Any.new(child.to_a))
    end

    # Returns a shallow copy of the array.
    def to_a : Array(TOML::Any)
      @values.dup
    end
  end
end
