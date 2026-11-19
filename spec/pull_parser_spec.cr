require "./spec_helper"
require "../src/toml/json"

private enum CompassPoint
  NorthEast
  West
end

private struct SampleSeries
  include TOML::Serializable
  getter points : Array(CompassPoint)
  getter counts : Hash(String, Array(Int64 | Float64))
  getter readings : Array(Float64)
end

private struct NoteBook
  include TOML::Serializable
  getter notes : Hash(String, Array(String))

  def initialize(reader : TOML::PullParser) : Nil
    @notes = {} of String => Array(String)
    reader.read_object do |key|
      if key.starts_with?("_")
        reader.skip
      else
        @notes[key] = Array(String).new(reader)
      end
    end
  end

  def to_toml(writer : TOML::Builder) : Nil
    writer.object { notes.each { |key, lines| writer.field(key, lines) } }
  end
end

private module ChordCodec
  # The two-argument writer identifies the cursor protocol for an untyped reader.
  def self.from_toml(reader) : String # ameba:disable Typing/MethodParameterTypeRestriction
    notes = [] of String
    reader.read_array { notes << reader.read_string }
    notes.join("-")
  end

  def self.to_toml(chord : String, writer : TOML::Builder) : Nil
    writer.array { chord.split('-').each { |note| writer.string(note) } }
  end
end

private struct ScoreBook
  include TOML::Serializable
  getter books : Array(NoteBook)
  @[TOML::Field(converter: ChordCodec)]
  getter chord : String
end

private record Beats, count : Int32 do
  def initialize(reader : TOML::PullParser) : Nil
    @count = Int32.new(reader)
  end

  def to_toml(builder : TOML::Builder) : Nil
    builder.scalar(count)
  end
end

private struct FreeForm
  include TOML::Serializable
  getter metadata : ::JSON::Any
  getter beats : Beats
end

private class CircularNote
  include TOML::Serializable

  def to_toml(builder : TOML::Builder) : Nil
    builder.array("notes", &.table(&.field("again", self)))
  end
end

describe TOML::PullParser do
  it "honors custom constructors, converter readers and builders inside generated models" do
    input = %(books = [{verse = ["spring"], _draft = [1, 2]}]\nchord = ["A", "C"])
    score = ScoreBook.from_toml(input)
    score.books.first.notes.should eq({"verse" => ["spring"]})
    score.chord.should eq("A-C")
    ScoreBook.from_toml(score.to_toml).should eq(score)
    NoteBook.new(TOML::PullParser.new("title = []")).notes.should eq({"title" => [] of String})
  end

  it "applies aliases and integer widening recursively and prefers the exact numeric union branch" do
    sample = SampleSeries.from_toml(%(points = ["north_east"]\ncounts = {a = [4, 4.0]}\nreadings = [5, 6.5]))
    sample.points.should eq([CompassPoint::NorthEast])
    sample.counts["a"][0].should be_a(Int64)
    sample.counts["a"][1].should be_a(Float64)
    sample.readings.should eq([5.0, 6.5])
  end

  it "supports value constructors and writers on ordinary types" do
    score = FreeForm.from_toml(%(metadata = {key = [7, true]}\nbeats = 3))
    score.beats.count.should eq(3)
    FreeForm.from_toml(score.to_toml).should eq(score)
    values = [score.beats, "rest"]
    TOML.build(&.field("sequence", values)).should eq(%(sequence = [3, "rest"]\n))
    (String | Int64).new(TOML::PullParser.new(TOML::Any.new(7))).should eq(7)
  end

  it "builds nested unnamed containers as a field value" do
    doc = TOML.build do |builder|
      builder.object do
        builder.field("bars") { builder.array { builder.object { builder.field("count", 2) } } }
      end
    end
    TOML.parse(doc)["bars"][0]["count"].as_i.should eq(2)
  end

  it "detects cycles across custom writers and nested builders" do
    expect_raises(TOML::SerializableError, /cyclic/) { CircularNote.from_toml("").to_toml }
  end

  it "rejects missing and repeated consumption" do
    expect_raises(TOML::SerializableError, /unconsumed/) { TOML::PullParser.new("b = true").read_object { } }
    reader = TOML::PullParser.new(TOML::Any.new(false))
    reader.read_bool.should be_false
    expect_raises(TOML::SerializableError, /already consumed/) { reader.skip }
  end
end

describe TOML::JSON do
  it "converts nested values without changing integer and float types" do
    json = ::JSON.parse(%({"a":[false,3,3.0,{"b":"c"}]}))
    node = TOML::JSON.from_json(json)
    node["a"][1].raw.should be_a(Int64)
    node["a"][2].raw.should be_a(Float64)
    TOML::JSON.to_json(node).should eq(json)
  end

  it "distinguishes shared children from cyclic input" do
    parts = [] of ::JSON::Any
    shared = ::JSON::Any.new(parts)
    TOML::JSON.from_json(::JSON::Any.new([shared, shared])).as_a.size.should eq(2)
    parts << shared
    expect_raises(TOML::SerializableError, /cyclic/) { TOML::JSON.from_json(shared) }
    items = [] of TOML::Any
    items << TOML::Any.new(items)
    expect_raises(TOML::SerializableError, /cyclic/) { TOML::JSON.to_json(items.first) }
  end

  it "represents temporal values as strings and rejects non-finite JSON numbers" do
    instant = TOML::Any.new(Time.utc(2024, 1, 2, nanosecond: 123))
    TOML::JSON.to_json(instant).as_s.should eq("2024-01-02T00:00:00.000000123Z")
    expect_raises(TOML::SerializableError, /non-finite/) { TOML::JSON.to_json(TOML::Any.new(Float64::NAN)) }
  end

  it "reports the exact location of an unrepresentable null" do
    error = expect_raises(TOML::JSON::NullError) { TOML::JSON.from_json(::JSON.parse(%({"a.b":[null]}))) }
    error.path.should eq(%($["a.b"][0]))
  end
end
