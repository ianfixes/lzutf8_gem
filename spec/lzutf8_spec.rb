require 'spec_helper'
require 'json'
require 'base64'

RSpec.describe LZUTF8 do
  context "gem" do
    it "has a version number" do
      expect(LZUTF8::VERSION).not_to be nil
    end
  end

  # my test cases
  test_cases = {
    spec_file_itself: IO.read(__FILE__),
    oversized_match: ("A" * ((2 * LZUTF8::MAXIMUM_SEQUENCE_LENGTH) + 2))
  }

  # lukejpreston/xunit-viewer test cases
  full_path = "/home/luke/Projects/lukejpreston/xunit-viewer/data/"
  fullpathify = Proc.new { |n| "#{full_path}#{n}" }
  decompress_cases = JSON.parse(IO.read(File.expand_path("xunit_viewer.json", __dir__)))
  bad_on_purpose = [
    #"invalid.xml",
  ].map(&fullpathify)
  no_compression = [
    "invalid.xml",
    "subfolder/_thingy.xml"
  ].map(&fullpathify)

  # incorrect test cases
  context("Valid inputs") do
    it "rejects non-strings" do
      expect { LZUTF8.compress(nil) }.to raise_error(ArgumentError)
      expect { LZUTF8.decompress(nil) }.to raise_error(ArgumentError)
    end
  end

  # iterate over my test cases
  context "compression" do
    test_cases.each do |name, contents|
      it "compresses and decompresses #{name} losslessly" do
        contents = IO.read(__FILE__)
        compressed_contents = LZUTF8.compress(contents)
        expect(compressed_contents.encoding.name).to eq(Encoding::UTF_8.to_s)

        if no_compression.include?(name)
          expect(compressed_contents.length).to be == contents.length
        else
          expect(compressed_contents.length).to be < contents.length
        end

        decompressed_contents = LZUTF8.decompress(compressed_contents)
        expect(decompressed_contents).to eq(contents)
        expect(decompressed_contents.encoding.name).to eq(Encoding::UTF_8.to_s)
      end

      it "decompresses uncompressed text without corruption" do
        test_cases.each do |name, contents|
          contents = IO.read(__FILE__)

          decompressed_contents = LZUTF8.decompress(contents)
          expect(decompressed_contents).to eq(contents)
        end
      end
    end
  end

  # spot check special case features
  context "edge cases" do
    it "compresses up to the match limit" do
      expect(LZUTF8.compress(test_cases[:oversized_match])).to end_with("A")
    end
  end


  context "decompression xunit cases" do
    decompress_cases.each do |h|
      file = h["file"]
      local = file[full_path.length..-1]
      decoded = Base64.decode64(h["contents"])
      if bad_on_purpose.include?(file)
        it "fails as expected on #{local}" do
          expect { LZUTF8.decompress(decoded) }.to raise_error
        end
      else
        it "decompresses #{local}" do
          contents = LZUTF8.decompress(decoded)
          if no_compression.include?(file)
            expect(contents.length).to be == decoded.length
          else
            expect(contents.size).to be > decoded.size
          end
        end
      end
    end
  end

  context "compression xunit cases" do
    Dir[File.expand_path("./data", __dir__) + "/**/*"].select { |p| File.file?(p) }.each do |file|
      it "compresses and decompresses #{file.slice((__dir__.length + 1)..-1)}" do
        File.open(file, "r:bom|utf-8") do |f|
          uncompressed = f.read.force_encoding(Encoding::UTF_8)
          compressed = LZUTF8.compress(uncompressed)
          expect(uncompressed.size).to be >= compressed.size
          expect(uncompressed.encoding.name).to eq(compressed.encoding.name)

          decompressed = LZUTF8.decompress(compressed)
          expect(decompressed).to eq uncompressed
        end
      end
    end
  end

end
