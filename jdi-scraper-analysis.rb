require 'fileutils'
require 'pathname'

class analyzeJdiData

  OUTPUT_DIR = Pathname.new(__dir__).join("data").expand_path

end
