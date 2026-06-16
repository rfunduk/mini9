# ENGINE native=Data_File ruby=DataFile

class DataFile
  include NativeHandle

  attr_reader :path
  def to_s = "DataFile(path: #{path})"
end
