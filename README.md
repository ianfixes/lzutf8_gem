# LZUTF8 Gem - providing `lzutf8`
[![Gem Version](https://badge.fury.io/rb/lzutf8.svg)](https://rubygems.org/gems/lzutf8)
[![Documentation](http://img.shields.io/badge/docs-rdoc.info-blue.svg)](http://www.rubydoc.info/gems/lzutf8/0.0.1)

A ruby gem containing an implementation of LZUTF-8 compression and decompression

* `LZUTF8.compress("some input")`
* `LZUTF8.decompress("some compressed input")`

## Algorithm

This is a port of https://github.com/rotemdan/lzutf8.js/

The trick is to create a set of pointer sequences that coexist with UTF-8 encoding.  The pointers include fields for a matched sequence length (bits indicated with `l`) and a distance (backward) that the sequence can be found in the encoded string (bits indicated with `d`).

|Bytes |Sized pointer sequence      | UTF-8 Codepoint sequence
|------|----------------------------|-------------------------
| 1    |n/a                         |`0xxxxxxx`
| 2    |`110lllll 0ddddddd`         |`110xxxxx 10xxxxxx`
| 3    |`111lllll 0ddddddd dddddddd`|`1110xxxx 10xxxxxx 10xxxxxx`
| 4    |n/a                         |`11110xxx 10xxxxxx 10xxxxxx 10xxxxxx`

Note that this allows for 5 bits (representing maxiumum 31 bytes) of matched sequence and up to 15 bits (representing maximum 32767 bytes) of distance to the matched sequence.

### Compressing

The text is converted to bytes of UTF-8.  Byte sequences of `4 <= length` and `length <= 31` are replaced where possible with sized pointer sequences -- pointing to a relative location up to 32767 bytes where the sequence can be found.

Hash every 4-byte sequence in the input string and use it to store the position of that sequence.  Each hash bucket will then contain an array of locations where that starting position can be found.

For example, the string `abcdefabcd` would produce the following table:

|hash  |pointers
|------|-------
|`abcd`|0, 6
|`bcde`|1
|`cdef`|2
|`defa`|3
|`efab`|4
|`fabc`|5

The output string would be identical to the input as far as `abcdef` after which a sized pointer representing a distance of 6 and a length of 4 would be appended: `0b11000100_00000110`

### Decompressing

Scan for sized pointers based on the bit sequences listed above.  When encountered, replace them with the text at the pointed-to location of the desired length.

> **Note:** it is legal for the desired length to be _longer_ than the requested distance (e.g. a repeated individual character might produce a sized pointer that requests length 31 from distance 1).  The text extracted from the pointer should be repeated to fill the desired length.
