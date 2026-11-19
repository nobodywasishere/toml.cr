module TOML
  # Configures how an instance variable maps to TOML. See Serializable.
  annotation Field
  end

  # Raised when TOML and a serializable object's fields cannot be mapped.
  class SerializableError < Exception
  end

  # :nodoc:
  class AmbiguousUnionError < SerializableError
  end

  # Maps instance variables to a TOML table. Including this module adds
  # `self.from_toml`, `#to_toml`, and `#to_toml_table` to the type.
  #
  # Fields use their instance variable names by default. Missing fields keep
  # their defaults or become nil when nilable. Nil fields are omitted on output
  # if they have no initializer or are initialized to literal nil. Other
  # initializers can restore a value on read, so writing nil raises
  # `TOML::SerializableError`. Two emitted fields cannot share a TOML key.
  # Readable fields must also have distinct keys. Reading a union raises
  # `TOML::SerializableError` if multiple members accept the value.
  # Include `TOML::Serializable::Strict` to reject unknown keys. Output-only
  # keys are recognized in strict mode and skipped during deserialization.
  # Model initialization hooks run after union selection. Converters may be
  # called while testing candidates and should avoid side effects.
  #
  # `@[TOML::Field]` supports these options:
  #
  # - `key` renames the TOML key using a string literal or a constant defined
  #   with a string literal. Symbol literals also use their name as the key.
  # - `ignore` skips the field in both directions when true.
  # - `ignore_deserialize` skips the field on input when true. Both options
  #   accept boolean literals and constants defined with boolean literals.
  # - `ignore_serialize` skips the field on output if the expression is truthy.
  # - `converter` overrides conversion. It defines `from_toml(TOML::Any)`
  #   and `to_toml(value)`, which returns a value representable in TOML. To
  #   report invalid input, a converter can raise `TOML::SerializableError`.
  module Serializable
    macro included
      # Reads a TOML document from a string or IO.
      def self.from_toml(input : ::String | ::IO) : self
        from_toml(::TOML.parse(input))
      end

      # Reads an already parsed TOML table.
      def self.from_toml(table : ::TOML::Table) : self
        decoder = ::TOML::Serializable::Decoder.new
        decoder.finish(__toml_prepare(table, decoder))
      end

      # :nodoc:
      # Compare the runtime class with the declaration even inside unions
      # whose member types are private to the model's source file.
      def self.__toml_matches_type?(type : T.class) : ::Bool forall T
        {% verbatim do %}
          {% if T.union? %}
            {{ T.union_types.includes?(@type.instance) }}
          {% else %}
            {{ T == @type.instance }}
          {% end %}
        {% end %}
      end

      # :nodoc:
      def self.__toml_prepare(table : ::TOML::Table, decoder : ::TOML::Serializable::Decoder) : ::Proc(self)
        unknown = decoder.unknown_keys(table, self, typeof(__toml_keys(self)))
        fields = __toml_read_fields(self, table, decoder)
        ->{
          instance = allocate
          instance.initialize(__toml_fields: fields, __toml_unknown: unknown)
          ::GC.add_finalizer(instance) if instance.responds_to?(:finalize)
          instance
        }
      end

      # :nodoc:
      def initialize(*, __toml_fields fields : F, __toml_unknown unknown : ::Array(::String)) forall F
        {% verbatim do %}
          {% for ivar in @type.instance_vars %}
            {% if F.keys.includes?(ivar.id) %}
              {% if ivar.has_default_value? || ivar.type.nilable? %}
                if plan = fields[{{ ivar.id.symbolize }}]
                  @{{ ivar }} = plan.call
                end
              {% else %}
                @{{ ivar }} = fields[{{ ivar.id.symbolize }}].not_nil!.call
              {% end %}
            {% end %}
          {% end %}
        {% end %}
        unknown.each { |key| on_unknown_toml_attribute(key) }
        after_initialize
      end

      __toml_define_layer
      macro inherited
        __toml_define_layer
      end
    end

    # :nodoc:
    # Each super call compiles its fields in the class that declared them.
    # Keep the concrete model for allocation and the declaring scope for lookup.
    macro __toml_define_layer
      macro finished
        __toml_bind_external_scopes
      end

      # :nodoc:
      def to_toml_table(encoder : ::TOML::Serializable::Encoder) : ::TOML::Table
        table = ::TOML::Table.new
        __toml_write_layers(::Union(typeof(self)), encoder, table)
        table
      end

      def self.__toml_keys(scope : S.class) forall S
        {% verbatim do %}
          {% begin %}
            {% if S.superclass && S.superclass <= ::TOML::Serializable %}
              inherited = super({{ S.superclass }})
            {% else %}
              inherited = ::NamedTuple.new
            {% end %}
            inherited.merge(S.__toml_map_fields(field_keys))
          {% end %}
        {% end %}
      end

      def self.__toml_read_fields(scope : S.class, table : ::TOML::Table, decoder : ::TOML::Serializable::Decoder) forall S
        {% verbatim do %}
          {% begin %}
            {% if S.superclass && S.superclass <= ::TOML::Serializable %}
              inherited = super({{ S.superclass }}, table, decoder)
            {% else %}
              inherited = ::NamedTuple.new
            {% end %}
            model = self
            inherited.merge(S.__toml_map_fields(prepare_model))
          {% end %}
        {% end %}
      end

      def __toml_write_layers(scope : S.class, encoder : ::TOML::Serializable::Encoder, table : ::TOML::Table) : ::Nil forall S
        {% verbatim do %}
          {% if S.superclass && S.superclass <= ::TOML::Serializable %}
            super({{ S.superclass }}, encoder, table)
          {% end %}
          S.__toml_map_fields(write_model)
        {% end %}
      end
    end

    # :nodoc:
    # An annotation can contain an arbitrary instance expression. Compile it
    # inside its source namespace while evaluating it on the actual model.
    macro __toml_bind_external_scopes
      {%
        parent = @type.superclass
        bound = parent && parent <= ::TOML::Serializable ? parent.ancestors : [] of Nil
        roots = [::Reference, ::Value, ::Struct, ::TOML::Serializable, ::TOML::Serializable::Strict]
        excluded = roots.reduce(bound) { |list, root| list + [root] + root.ancestors }
      %}
      {% for ancestor, index in @type.ancestors.reject { |type| type <= ::TOML::Serializable || excluded.includes?(type) } %}
        private alias TOMLFieldSource{{ index }} = {{ ancestor.name(generic_args: false) }}
        {% unless parse_type(ancestor.name(generic_args: false).stringify).resolve.constants.includes?("TOMLDeclaredFieldScope".id) %}
          module TOMLFieldSource{{ index }}::TOMLDeclaredFieldScope
            struct Tag
            end

            include ::TOML::Serializable::FieldMapping

            def self.keys(layer : M.class, origin : O.class, names : F.class) forall M, O, F
              {% verbatim do %}
                {% begin %}
                  __toml_map_declared_fields(field_keys, {{ M }}, {{ O }}, {{ F }})
                {% end %}
              {% end %}
            end

            def self.read(model, layer : M.class, origin : O.class, names : F.class, table, decoder) forall M, O, F
              {% verbatim do %}
                {% begin %}
                  __toml_map_declared_fields(prepare_model, {{ M }}, {{ O }}, {{ F }})
                {% end %}
              {% end %}
            end

            def __toml_write_external(tag : Tag.class, layer : M.class, origin : O.class, names : F.class, encoder, table) : ::Nil forall M, O, F
              {% verbatim do %}
                {% begin %}
                  {{ O.name(generic_args: false) }}::TOMLDeclaredFieldScope.__toml_map_declared_fields(write_model, {{ M }}, {{ O }}, {{ F }})
                {% end %}
              {% end %}
            end
          end
        {% end %}
        include TOMLFieldSource{{ index }}::TOMLDeclaredFieldScope
      {% end %}
    end

    # :nodoc:
    macro __toml_map_fields(operation)
      {%
        scope = @type.instance
        parent = scope.superclass
        inherited = parent && parent <= ::TOML::Serializable ? parent.instance_vars.map(&.name) : [] of Nil
        groups = {} of Nil => Nil
        scope.instance_vars.reject { |ivar| inherited.includes?(ivar.name) }.each do |ivar|
          # Reflected ivars include declarations from mixins. Match the effective
          # annotation's source location before assigning its lexical scope.
          effective = ivar.annotation(::TOML::Field)
          owners = scope.ancestors.select do |ancestor|
            ancestor.instance_vars.any? do |field|
              next_annotation = field.annotation(::TOML::Field)
              field.name == ivar.name && (!effective || (next_annotation &&
                effective.filename == next_annotation.filename &&
                effective.line_number == next_annotation.line_number &&
                effective.column_number == next_annotation.column_number))
            end
          end
          origin = owners.empty? ? scope : owners.last
          groups[origin] = [] of Nil unless groups[origin]
          groups[origin] << ivar.name
        end
        write = operation.id == "write_model"
      %}
      {% unless write %} ::NamedTuple.new {% end %}
      {% for origin, names in groups %}
        {% unless write %}.merge( {% end %}
        {% field_names = names.map { |name| "#{name}: ::Bool".id } %}
        {% if origin == scope %}
          S.__toml_map_declared_fields({{ operation }}, nil, nil, ::NamedTuple({{ field_names.splat }}))
        {% elsif write %}
          __toml_write_external({{ origin.name(generic_args: false) }}::TOMLDeclaredFieldScope::Tag, S, {{ origin }}, ::NamedTuple({{ field_names.splat }}), encoder, table)
        {% elsif operation.id == "field_keys" %}
          {{ origin.name(generic_args: false) }}::TOMLDeclaredFieldScope.keys(S, {{ origin }}, ::NamedTuple({{ field_names.splat }}))
        {% else %}
          {{ origin.name(generic_args: false) }}::TOMLDeclaredFieldScope.read(self, S, {{ origin }}, ::NamedTuple({{ field_names.splat }}), table, decoder)
        {% end %}
        {% unless write %}){% end %}
      {% end %}
    end

    # :nodoc:
    module FieldMapping
      macro __toml_map_declared_fields(operation, model_type, source_type, names)
        {% mapping = [] of Nil %}
        {% model = model_type ? model_type.resolve : @type.instance %}
        {% source = source_type ? source_type.resolve : @type.instance %}
        {% for ivar in model.instance_vars.select { |field| names.resolve.keys.includes?(field.name) } %}
          {%
            ann = ivar.annotation(::TOML::Field)
            flags = {} of Nil => Nil
          %}
          {% for option in [:ignore, :ignore_deserialize] %}
            {%
              flag = (ann && ann[option]) || false
              flag = flag.resolve if flag.is_a?(Path)
              unless flag.is_a?(BoolLiteral)
                raise "TOML field #{ivar}: #{option.id} must be a boolean literal or constant"
              end
              flags[option] = flag
            %}
          {% end %}
          {%
            unless flags[:ignore]
              key = (ann && ann[:key]) || ivar.id.stringify
              key = key.resolve if key.is_a?(Path)
              key = key.id.stringify if key.is_a?(SymbolLiteral)
              unless key.is_a?(StringLiteral)
                raise "TOML field key for #{ivar} must be a literal string or symbol, or a constant defined with one"
              end
              declaration = nil
              unless ann && ann[:converter]
                getter = source.methods.find { |method| method.name == ivar.name && method.args.empty? && method.body.stringify == "@#{ivar.id}" }
                if getter && (getter.return_type.is_a?(Union) || getter.return_type.is_a?(Generic))
                  declaration = getter.return_type
                end
              end
              skip_write = ann && ann[:ignore_serialize]
              if skip_write.is_a?(Path) && skip_write.resolve.is_a?(BoolLiteral)
                skip_write = skip_write.resolve
              end
              mapping << {
                name:             ivar.id.symbolize,
                key:              key,
                declaration:      declaration,
                readable:         !flags[:ignore_deserialize],
                skip_write:       skip_write,
                converter:        ann && ann[:converter],
                required:         !ivar.has_default_value? && !ivar.type.nilable?,
                restores_default: ivar.has_default_value? && !ivar.default_value.is_a?(NilLiteral),
              }
            end
          %}
        {% end %}
        ::TOML::Serializable.__toml_{{ operation.id }}({{ mapping.splat }})
      end
    end

    include FieldMapping

    # :nodoc:
    # Prefix wire keys because Crystal disallows empty named tuple keys.
    macro __toml_field_keys(*mapping)
      ::NamedTuple.new(
        {% for field in mapping %}
          {{ field[:name].id }}: ::NamedTuple.new({{ "_#{field[:key].id}" }}: {{ field[:readable] ? true : nil }}),
        {% end %}
      )
    end

    # :nodoc:
    macro __toml_prepare_model(*mapping)
      ::NamedTuple.new(
        {% for field in mapping %}
          {% if field[:readable] %}
            {% name = field[:name] %}
            {% key = field[:key] %}
            {{ name.id }}: decoder.field(table, model.name, {{ key }}, required: {{ field[:required] }}) do |value|
              {% if converter = field[:converter] %}
                converted = {{ converter }}.from_toml(value)
                ->{ converted }
              {% elsif declaration = field[:declaration] %}
                decoder.prepare(value, ::Union(typeof(model.allocate.@{{ name.id }})), ::TOML::Serializable.__toml_shape(::Tuple({{ declaration }})))
              {% else %}
                decoder.prepare(value, ::Union(typeof(model.allocate.@{{ name.id }})))
              {% end %}
            end,
          {% end %}
        {% end %}
      )
    end

    # :nodoc:
    macro __toml_write_model(*mapping)
      {% for field in mapping %}
        {% name = field[:name] %}
        {% skip = field[:skip_write] %}
        {% unless skip == true %}
          {% key = field[:key] %}
          {% if skip %}
            unless {{ skip }}
          {% end %}
          %value = @{{ name.id }}
          if %value.nil?
            {% if field[:restores_default] %}
              raise ::TOML::SerializableError.new("#{self.class} field #{ {{ key }}.inspect } is nil and omission can restore its default")
            {% end %}
          else
            if table.has_key?({{ key }})
              raise ::TOML::SerializableError.new("Duplicate TOML output key #{ {{ key }}.inspect } for #{self.class} field #{ {{ name.id.stringify }}.inspect }")
            end
            {% if converter = field[:converter] %}
              table[{{ key }}] = encoder.write({{ converter }}.to_toml(%value))
            {% elsif field[:readable] && (declaration = field[:declaration]) %}
              table[{{ key }}] = encoder.write_typed(%value, ::Union(typeof(@{{ name.id }})), ::TOML::Serializable.__toml_shape(::Tuple({{ declaration }})))
            {% elsif field[:readable] %}
              table[{{ key }}] = encoder.write_typed(%value, ::Union(typeof(@{{ name.id }})))
            {% else %}
              table[{{ key }}] = encoder.write(%value)
            {% end %}
          end
          {% if skip %}
            end
          {% end %}
        {% end %}
      {% end %}
    end

    def to_toml : String
      TOML.dump(to_toml_table)
    end

    def to_toml(io : IO) : Nil
      TOML.dump(to_toml_table, io)
    end

    def to_toml_table : TOML::Table
      Encoder.new.write(self).as_h
    end

    # Called after an object has been deserialized.
    protected def after_initialize
    end

    protected def on_unknown_toml_attribute(key : String)
    end

    # Rejects TOML keys that do not map to a declared, non-ignored field.
    module Strict
    end

    # :nodoc:
    # Keep the declared branches separate before Crystal merges sibling types.
    # A nil shape delegates to the ordinary typed codec, including its scalar
    # collection fast path. Collections carry their element or value shape.
    macro __toml_shape(wrapped)
      {% type = wrapped.type_vars.first %}
      {% generic = type.is_a?(Generic) ? type.name.resolve? : nil %}
      {% if type.is_a?(Union) || generic == ::Union %}
        {% branches = type.is_a?(Union) ? type.types : type.type_vars %}
        (::Tuple.new {% for branch in branches %} + ::TOML::Serializable.alternatives(
          {{ branch }}, ::TOML::Serializable.__toml_shape(::Tuple({{ branch }}))
        ) {% end %})
      {% elsif generic == ::Array || generic == ::Hash %}
        ::TOML::Serializable.collection_shape(::TOML::Serializable.__toml_shape(::Tuple({{ type.type_vars.last }})))
      {% else %}
        nil
      {% end %}
    end

    # :nodoc:
    record CollectionShape(S), element : S

    def self.collection_shape(element : Nil) : Nil
      nil
    end

    def self.collection_shape(element : S) : CollectionShape(S) forall S
      CollectionShape.new(element)
    end

    def self.alternatives(type : T.class, shape : Tuple) : Tuple forall T
      shape
    end

    def self.alternatives(type : T.class, shape : CollectionShape?) : Tuple forall T
      {% if T.union? %}
        {
          {% for index in 0...T.union_types.size %}
            {T::T[{{ index }}], shape},
          {% end %}
        }
      {% else %}
        { {type, shape} }
      {% end %}
    end

    # :nodoc:
    class Decoder
      private alias Scalar = Bool | String | TOML::Temporal | TOML::Any

      protected getter ambiguity : AmbiguousUnionError? = nil

      # Prepare candidate values without running serializable initialization hooks.
      # Keep a nested ambiguity provisional until the whole candidate has matched.
      def finish(plan : Proc(T)) : T forall T
        if error = @ambiguity
          raise error
        end
        plan.call
      end

      def unknown_keys(table : TOML::Table, owner : T.class, keys : K.class) : Array(String) forall T, K
        {% begin %}
          {% readable = {} of Nil => Nil %}
          {% known = [] of Nil %}
          {% for name in K.keys %}
            {% entry = K[name] %}
            {% encoded_key = entry.keys.first %}
            {% key = encoded_key.stringify[1..-1] %}
            {% known << key %}
            {% if entry[encoded_key] != Nil %}
              {% if previous = readable[key] %}
                {% raise "Duplicate TOML input key #{key} for #{T} fields #{previous} and #{name}" %}
              {% end %}
              {% readable[key] = name %}
            {% end %}
          {% end %}
          unknown = table.keys
          {% unless known.empty? %}
            unknown.reject! { |key| { {{ known.splat }} }.includes?(key) }
          {% end %}
          {% if T <= ::TOML::Serializable::Strict %}
            if key = unknown.first?
              raise SerializableError.new("Unknown TOML field #{key.inspect} for #{owner}")
            end
          {% end %}
          unknown
        {% end %}
      end

      def field(table : TOML::Table, owner : String, key : String, *, required : Bool, & : TOML::Any -> Proc(T)) : Proc(T)? forall T
        if value = table[key]?
          previous = @ambiguity
          plan = with_field_context(owner, key) { yield value }
          if previous.nil? && (error = @ambiguity)
            @ambiguity = AmbiguousUnionError.new(field_message(owner, key, error), error)
          end
          -> : T { with_field_context(owner, key) { plan.call } }
        elsif required
          raise SerializableError.new("Missing TOML field #{key.inspect} for #{owner}")
        end
      end

      private def with_field_context(owner, key, &)
        yield
      rescue error : SerializableError | ArgumentError | TypeCastError | OverflowError | KeyError | IndexError
        message = field_message(owner, key, error)
        raise error.is_a?(AmbiguousUnionError) ? AmbiguousUnionError.new(message, error) : SerializableError.new(message, error)
      end

      private def field_message(owner, key, error)
        "#{owner} field #{key.inspect}: #{error.message}"
      end

      def prepare(value : TOML::Any, type : T.class, shape : Nil) : Proc(T) forall T
        prepare(value, type)
      end

      def prepare(value : TOML::Any, type : Array(T).class, shape : CollectionShape? = nil) : Proc(Array(T)) forall T
        source = expect(value, Array(TOML::Any))
        {% if !T.union? && (T <= Scalar || T < Int || T < Float || T < Enum) %}
          decoded = source.map { |element| read_scalar(element, T) }
          -> { decoded }
        {% else %}
          items = source.map { |element| prepare(element, T, shape.try(&.element)) }
          -> : Array(T) { items.map(&.call) }
        {% end %}
      end

      def prepare(value : TOML::Any, type : Hash(String, T).class, shape : CollectionShape? = nil) : Proc(Hash(String, T)) forall T
        source = expect(value, TOML::Table)
        {% if !T.union? && (T <= Scalar || T < Int || T < Float || T < Enum) %}
          decoded = source.transform_values { |element| read_scalar(element, T) }
          -> { decoded }
        {% else %}
          items = source.transform_values { |element| prepare(element, T, shape.try(&.element)) }
          -> : Hash(String, T) { items.transform_values(&.call) }
        {% end %}
      end

      def prepare(value : TOML::Any, type : T.class) : Proc(T) forall T
        {% if T.union? %}
          # T::T is the tuple of resolved member types of Union(*T). Indexing it
          # preserves file-private types without emitting their names as source.
          {% members = T.union_types.reject { |member| member == Nil } %}
          {% if members.size == 1 %}
            widen(prepare(value, T::T[{{ T.union_types.first == Nil ? 1 : 0 }}]), T)
          {% else %}
            prepare(value, T, Serializable.alternatives(T, nil))
          {% end %}
        {% elsif T <= TOML::Serializable && T.abstract? %}
          {% raise "Cannot determine concrete TOML members for #{T}; use a TOML field converter" %}
        {% elsif T <= TOML::Serializable %}
          T.__toml_prepare(expect(value, TOML::Table), self)
        {% else %}
          decoded = read_scalar(value, T)
          -> : T { decoded }
        {% end %}
      end

      def prepare(value : TOML::Any, type : T.class, members : Tuple(*M)) : Proc(T) forall T, M
        selected = nil
        selected_type = nil

        {% begin %}
          {% seen = [] of Nil %}
          {% for branch, index in M %}
            {% member = branch.type_vars.first.instance %}
            {% unless member == Nil || seen.includes?(member) %}
              {% seen << member %}
              member_type, shape = members[{{ index }}]
              candidate = Decoder.new
              if plan = candidate.try_prepare(value, member_type, shape)
                if error = candidate.ambiguity
                  @ambiguity ||= error
                  return widen(plan, T)
                end
                if previous_type = selected_type
                  @ambiguity ||= AmbiguousUnionError.new("Ambiguous TOML value for #{T}: matches #{previous_type} and #{member_type}")
                  return selected.not_nil!
                end
                selected = widen(plan, T)
                selected_type = member_type.to_s
              end
            {% end %}
          {% end %}
        {% end %}
        selected || raise SerializableError.new("Expected #{T}, got #{value.raw.class}")
      end

      protected def try_prepare(value : TOML::Any, type : T.class, shape : (Tuple | CollectionShape)?) : Proc(T)? forall T
        prepare(value, type, shape)
      rescue SerializableError
        nil
      end

      private def widen(plan : Proc(U), type : T.class) : Proc(T) forall T, U
        -> : T { plan.call.as(T) }
      end

      private def read_scalar(value : TOML::Any, type : T.class) : T forall T
        {% if T == TOML::Any %}
          value
        {% elsif T < Int %}
          begin
            T.new(expect(value, Int64))
          rescue error : OverflowError
            raise TOML::SerializableError.new("Integer is outside the range of #{T}", error)
          end
        {% elsif T == Float32 || T == Float64 %}
          raw = expect(value, Float64)
          converted = T.new!(raw)
          if raw.finite? && converted.infinite?
            raise TOML::SerializableError.new("Float is outside the range of #{T}")
          end
          converted
        {% elsif T < Float %}
          raw = expect(value, Float64)
          raise SerializableError.new("Float is outside the range of #{T}") unless raw.finite?
          T.new(raw)
        {% elsif T < Enum %}
          self.class.read_enum(value, T)
        {% else %}
          expect(value, T)
        {% end %}
      end

      def self.read_enum(value : TOML::Any, type : T.class) : T forall T
        name = value.as_s? || raise SerializableError.new("Expected String, got #{value.raw.class}")
        {% if T.annotation(::Flags) %}
          name.split(" | ").reduce(T.new(0)) { |flags, part| flags | enum_member(part, T) }
        {% else %}
          enum_member(name, T)
        {% end %}
      end

      private def self.enum_member(name : String, type : T.class) : T forall T
        {% for member in T.constants %}
          return T.new({{ T.constant(member) }}) if name == {{ member.stringify }}
        {% end %}
        raise TOML::SerializableError.new("Unknown #{T} member #{name.inspect}")
      end

      private def expect(value : TOML::Any, type : T.class) : T forall T
        raw = value.raw
        return raw if raw.is_a?(T)
        raise TOML::SerializableError.new("Expected #{type}, got #{raw.class}")
      end
    end

    # :nodoc:
    class Encoder
      @ancestors = Set(UInt64).new

      def write(value : TOML::Any) : TOML::Any
        value
      end

      def write(value : Bool | Int | String | TOML::Temporal) : TOML::Any
        TOML::Any.new(value)
      rescue error : OverflowError
        raise TOML::SerializableError.new("TOML integer is outside the signed 64-bit range", error)
      end

      def write(value : Float) : TOML::Any
        TOML::Any.new(value)
      rescue error : ArgumentError
        raise TOML::SerializableError.new(error.message, error)
      end

      def write(value : Enum) : TOML::Any
        write(value.__toml_member_names)
      end

      def write(value : Array) : TOML::Any
        write_array(value) { |element| write(element) }
      end

      def write(value : Hash(String, T)) : TOML::Any forall T
        write_table(value) { |element| write(element) }
      end

      def write_typed(value : Array(T), type : U.class, shape : CollectionShape? = nil) : TOML::Any forall T, U
        unless value.class == Array(T)
          raise SerializableError.new("Cannot round-trip #{value.class} as #{type}; use a TOML field converter")
        end
        write_array(value) { |element| write_typed(element, T, shape.try(&.element)) }
      end

      def write_typed(value : Hash(String, T), type : U.class, shape : CollectionShape? = nil) : TOML::Any forall T, U
        unless value.class == Hash(String, T)
          raise SerializableError.new("Cannot round-trip #{value.class} as #{type}; use a TOML field converter")
        end
        write_table(value) { |element| write_typed(element, T, shape.try(&.element)) }
      end

      def write_typed(value : Object, type : T.class, shape : Nil) : TOML::Any forall T
        write_typed(value, type)
      end

      def write_typed(value : Object, type : T.class, members : Tuple(*M)) : TOML::Any forall T, M
        {% for index in 0...M.size %}
          if encoded = write_matching(value, *members[{{ index }}])
            return encoded
          end
        {% end %}
        raise SerializableError.new("Cannot round-trip #{value.class} as a declared union member; use a TOML field converter")
      end

      private def write_matching(value, member : T.class, shape) forall T
        if value.is_a?(T) && value.class == member
          write_typed(value, member, shape)
        end
      end

      def write_typed(value : Serializable, type : T.class) : TOML::Any forall T
        unless value.class.__toml_matches_type?(type)
          raise SerializableError.new("Cannot round-trip #{value.class} as #{type}; use a TOML field converter")
        end
        write(value)
      end

      def write_typed(value : Object, type : T.class) : TOML::Any forall T
        write(value)
      end

      private def write_array(value : Array, &) : TOML::Any
        with_container(value) { TOML::Any.new(value.map { |element| yield element }) }
      end

      private def write_table(value : Hash(String, T), &) : TOML::Any forall T
        with_container(value) do
          table = TOML::Table.new(initial_capacity: value.size)
          value.each do |key, element|
            raise ArgumentError.new("Duplicate TOML key #{key.inspect}") if table.has_key?(key)
            table[key] = yield element
          end
          TOML::Any.new(table)
        end
      end

      def write(value : Serializable) : TOML::Any
        with_container(value) { TOML::Any.new(value.to_toml_table(self)) }
      end

      def write(value : Nil) : TOML::Any
        raise TOML::SerializableError.new("TOML cannot represent nil inside an array or table")
      end

      private def with_container(value, &)
        if value.is_a?(Reference)
          id = value.object_id
          unless @ancestors.add?(id)
            raise TOML::SerializableError.new("TOML cannot represent cyclic data")
          end
          begin
            yield
          ensure
            @ancestors.delete(id)
          end
        else
          yield
        end
      end
    end
  end
end

struct Enum
  # :nodoc:
  def __toml_member_names : String
    {% for member in @type.constants %}
      return {{ member.stringify }} if value == {{ @type.constant(member) }}
    {% end %}

    {% if @type.annotation(::Flags) %}
      covered = self.class.new(0)
      names = [] of String
      {% for member in @type.constants %}
        flag = self.class.new({{ @type.constant(member) }})
        if includes?(flag) && !covered.includes?(flag)
          names << {{ member.stringify }}
          covered |= flag
        end
      {% end %}
      return names.join(" | ") if covered == self
    {% end %}

    raise TOML::SerializableError.new("Cannot encode #{inspect} as TOML: no matching enum member names")
  end
end
