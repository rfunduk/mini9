# ENGINE native=Data_File ruby=DataFile

class DataFile
  attr_reader :path
  def to_s = "DataFile(path: #{path})"
  alias_method :inspect, :to_s
end
