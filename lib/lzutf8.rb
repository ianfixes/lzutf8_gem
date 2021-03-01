require "lzutf8/version"

# LZUTF8 contains functions to compress and decompress UTF-8 text with the LZUTF-8 algorithm
# @author Ian Katz <ianfixes@gmail.com>
module LZUTF8

  MINIMUM_SEQUENCE_LENGTH = 4
  MAXIMUM_SEQUENCE_LENGTH = 31
  MAXIMUM_MATCH_DISTANCE = 32767

  # Extract the information contained in an LZUTF8 Sized Pointer
  #
  # @param bytes [Array<Integer>] an array of character codes
  # @return [Integer, Integer] the pointer length and distance
  def self.pointer_info(bytes)
    c1, c2, c3 = bytes
    length = c1 & 0b00011111
    # either llllll_0ddddddd or 0b111lllll_0ddddddd_dddddddd
    distance = if (c1 & 0b00100000).zero?
      c2
    else
      (c2 << 8) + c3
    end
    [length, distance]
  end

  # Explain a compressed (or uncompressed) UTF-8 string at the sequence-of-bits level by printing to STDOUT
  #
  # @param string [String] the input string
  def self.explain(string)
    raise ArgumentError unless string.is_a? String

    input = string.bytes
    position = -1
    outsize = 0

    pointer2 = lambda do |seq|
      c1, c2 = seq
      [c2].none?(&:nil?) &&
        (c1 & 0b11100000) == 0b11000000 &&
        (c2 & 0b10000000).zero?
    end

    pointer3 = lambda do |seq|
      c1, c2, c3 = seq
      [c2, c3].none?(&:nil?) &&
        (c1 & 0b11100000) == 0b11100000 &&
        (c2 & 0b10000000).zero?
    end

    codepoint1 = ->(seq) { (seq.first & 0b10000000).zero? }

    codepoint2 = lambda do |seq|
      c1, c2 = seq
      [c2].none?(&:nil?) &&
        (c1 & 0b11100000) == 0b11000000 &&
        (c2 & 0b11000000) == 0b10000000
    end

    codepoint3 = lambda do |seq|
      c1, c2, c3 = seq
      [c2, c3].none?(&:nil?) &&
        (c1 & 0b11110000) == 0b11100000 &&
        (c2 & 0b11000000) == 0b10000000 &&
        (c3 & 0b11000000) == 0b10000000
    end

    codepoint4 = lambda do |seq|
      c1, c2, c3, c4 = seq
      [c2, c3, c4].none?(&:nil?) &&
        (c1 & 0b11111000) == 0b11110000 &&
        (c2 & 0b11000000) == 0b10000000 &&
        (c3 & 0b11000000) == 0b10000000 &&
        (c4 & 0b11000000) == 0b10000000
    end

    binarize = proc { |bytes| "0b" + bytes.map { |b| b.to_s(2).rjust(8, '0') }.join("_") }
    dump = proc do |pos, bytes, inc, meaning|
      outsize += inc
      puts "#{pos.to_s.rjust(4, '0')} #{binarize.call(bytes)} #{meaning} OS=#{outsize}"
    end

    dumpc = proc { |pos, bytes| dump.call(pos, bytes, bytes.size, "literal - #{bytes.pack('C*')}") }
    dumpp = proc do |pos, bytes|
      length, distance = self.pointer_info(bytes)
      dump.call(pos, bytes, length, "pointer l=#{length} d=#{distance}")
    end

    until input.empty? do
      position += 1
      c1 = input.shift
      c2, c3, c4 = input[0, 3]
      sequence = [c1, c2, c3, c4]

      case sequence
      when codepoint1
        dumpc.call(position, [c1])
      when codepoint2
        dumpc.call(position, [c1, c2])
        position += 1.times { input.shift } # rubocop:disable Lint/UselessTimes
      when codepoint3
        dumpc.call(position, [c1, c2, c3])
        position += 2.times { input.shift }
      when codepoint4
        dumpc.call(position, [c1, c2, c3, c4])
        position += 3.times { input.shift }
      when pointer2
        dumpp.call(position, [c1, c2])
        position += 1.times { input.shift } # rubocop:disable Lint/UselessTimes
      when pointer3
        dumpp.call(position, [c1, c2, c3])
        position += 2.times { input.shift }
      else
        dump.call(position, [c1], 1, "Assumed part of a sequence")
      end
    end
  end

  # Decompress an LZUTF8-compressed string.
  #
  # Due to the nature of this decompression algorithm, any uncompressed UTF-8 string can be
  # passed to this function and will be returned unmodified
  #
  # @param string [String] The input LZUTF8-compressed string
  # @return [String] Uncompressed UTF-8 string
  def self.decompress(string)
    raise ArgumentError unless string.is_a? String

    input = string.bytes
    output = []
    until input.empty? do
      c1 = input.shift # consume
      c2 = input.first # peek
      next (output << c1) unless (c1 & 0b11000000) == 0b11000000 && (c2 & 0b10000000).zero?

      # By this point we know it's not a literal char and we must actually consume the 2nd byte
      # either llllll_0ddddddd or 0b111lllll_0ddddddd_dddddddd
      c2       = input.shift & 0b01111111
      length   = c1 & 0b00011111
      distance = (c1 & 0b00100000).zero? ? c2 : (c2 << 8) + input.shift # consume 3rd byte if needed

      # get text from pointer, wrap in enumartor, take data until length satisfied and append
      output += Enumerator.new { |y| loop { output[-distance, length].each { |v| y << v } } }.lazy.take(length).to_a
    end

    output.pack('C*').force_encoding(Encoding::UTF_8)
  end

  # Decompress a string using the LZUTF8 algorithm
  #
  # Due to the nature of this compression algorithm, only valid UTF-8 codepoints can be compressed;
  # arbitrary binary data will fail.
  #
  # @param string [String] The input string
  # @return [String] compresed string
  def self.compress(string)
    raise ArgumentError unless string.is_a? String

    input = string.bytes
    hash = {}
    match_score = proc { |dist, len| dist < 128 ? len * 1.5 : len } # 2 byte vs 3 byte compression

    pointer = -1
    output = []
    until pointer + 1 == input.size do
      pointer += 1
      c1, c2, c3, c4 = key = input[pointer, 4]
      key = key.pack('C*')
      next (output << c1) if [c2, c3, c4].any?(&:nil?) # near end of input, just iterate until it's consumed

      max_len = [input.size - pointer, MAXIMUM_SEQUENCE_LENGTH].min  # max length of a match
      matches = begin
        next (output << c1) if hash[key].nil? # no matches if no bucket

        hash[key].map do |start|              # all known bucket entries as [distance, length_of_match]
          matchable = input[pointer, max_len] # max length of the matchable input segment
          distance = pointer - start          # relative distance must be less than max expressable
          next nil if distance > MAXIMUM_MATCH_DISTANCE # this would mean a bucket entry we didn't clean up

          # linear comparison to find longest common prefix
          len = input[start, max_len].zip(matchable).index { |a, b| a.nil? || b.nil? || a != b }
          case len
          when nil then                   [distance, matchable.size] # hit end of input, fully matched
          when 0..MINIMUM_SEQUENCE_LENGTH then nil                   # no match
          else                            [distance, len - 1]        # index is the one BEFORE the mismatch
          end
        end
      ensure  # that the pointer is added to the hash for this sequence
        hash[key] = [] if hash[key].nil?
        hash[key] << pointer
        hash[key] = hash[key].select { |p| pointer - p < MAXIMUM_MATCH_DISTANCE } # prune too-distant matches
      end.compact

      best_match = matches.max { |a, b| match_score.call(a) <=> match_score.call(b) }
      next (output << c1) if best_match.nil?

      # Output a pointer to the match and advance the input pointer by the amount matched
      match_distance, match_length = best_match
      output += if match_distance < 0b10000000
        [0b11000000 | match_length, match_distance]
      else
        [0b11100000 | match_length, match_distance >> 8, match_distance & 0b00000000_11111111]
      end
      pointer += (match_length - 1)
    end
    output.pack('C*').force_encoding(Encoding::UTF_8)
  end
end
