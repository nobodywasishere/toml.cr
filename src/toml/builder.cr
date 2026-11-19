# Builds a TOML document from named fields and nested collections.
#
# Use `TOML.build` to write the completed document to a string or an IO.
class TOML::Builder
  @containers = [] of Any
  @root : Any?

  def initialize(@encoder = Serializable::Encoder.new) : Nil
  end

  # :nodoc:
  def self.capture(encoder : Serializable::Encoder, & : Builder ->) : Any
    builder = new(encoder)
    yield builder
    builder.result
  end

  protected def result : Any
    @root || raise SerializableError.new("TOML builder expected one value")
  end

  # Writes one value into the current array or at the root of a converter.
  def scalar(value : T) : Nil forall T
    append(@encoder.encode(value))
  end

  def string(value : String) : Nil
    scalar(value)
  end

  def object(&) : Nil
    container(Any.new(Table.new)) { yield }
  end

  def array(&) : Nil
    container(Any.new([] of Any)) { yield }
  end

  private def container(node : Any, &) : Nil
    @containers << node
    begin
      yield
    ensure
      @containers.pop
    end
    append(node)
  end

  private def append(node : Any) : Nil
    if parent = @containers.last?
      array = parent.as_a? || raise SerializableError.new("A TOML table value requires a field name")
      array << node
    elsif @root
      raise SerializableError.new("TOML builder expected one value")
    else
      @root = node
    end
  end

  # Adds a value under *key*. The key is literal, even if it contains dots.
  # Raises `ArgumentError` if the key is already present in this table.
  def field(key : String, value : T) : Nil forall T
    parent = @containers.last? || (@root ||= Any.new(Table.new))
    table = parent.as_h? || raise SerializableError.new("Cannot add a named field outside a TOML table")
    raise ArgumentError.new("Duplicate TOML key #{key.inspect}") if table.has_key?(key)
    table[key] = @encoder.encode(value)
  end

  # Adds the single value written by the block under *key*.
  def field(key : String, &) : Nil
    values = [] of Any
    @containers << Any.new(values)
    begin
      yield
    ensure
      @containers.pop
    end
    raise SerializableError.new("A TOML field requires exactly one value") unless values.size == 1
    field(key, values.first)
  end

  # Adds a nested table built by the block.
  def table(key : String, & : Builder ->) : Nil
    child = Builder.new(@encoder)
    yield child
    field(key, TOML::Any.new(child.to_toml_table))
  end

  # Adds an array built by the block.
  def array(key : String, & : ArrayBuilder ->) : Nil
    child = ArrayBuilder.new(@encoder)
    yield child
    field(key, TOML::Any.new(child.to_a))
  end

  # Returns a shallow copy of the document table.
  def to_toml_table : TOML::Table
    @root.try(&.as_h.dup) || Table.new
  end

  # Renders the current document as TOML.
  def to_toml : String
    TOML.dump(to_toml_table)
  end

  # Writes the current document to *io*.
  def to_toml(io : IO) : Nil
    TOML.dump(to_toml_table, io)
  end

  # Builds the sequence of values in a TOML array.
  class ArrayBuilder
    @values = Array(TOML::Any).new

    def initialize(@encoder = Serializable::Encoder.new) : Nil
    end

    # Appends a value to the array.
    def value(value : T) : Nil forall T
      @values << @encoder.encode(value)
    end

    # Appends a table built by the block.
    def table(& : Builder ->) : Nil
      child = Builder.new(@encoder)
      yield child
      value(TOML::Any.new(child.to_toml_table))
    end

    # Appends an array built by the block.
    def array(& : ArrayBuilder ->) : Nil
      child = ArrayBuilder.new(@encoder)
      yield child
      value(TOML::Any.new(child.to_a))
    end

    # Returns a shallow copy of the array.
    def to_a : Array(TOML::Any)
      @values.dup
    end
  end
end
