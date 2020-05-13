require "option_parser"
require "json"
require "file_utils"
require "log"

class ICrystal::Command
  USAGE = <<-USAGE
    Usage: icrystal [command] [options]

    Command:
        register                 register ICrystal kernel
        unregister               unregister ICrystal kernel
        kernel                   start a kernel
        help, --help, -h         show this help
        version, --version, -v   show version
    USAGE

  def self.run(options = ARGV)
    new(options).run
  end

  getter options

  def initialize(@options : Array(String))
  end

  def run
    command = options.first?
    case command
    when "register"
      force = options.includes?("--force")
      if registered_icrystal_path && !force
        STDERR.puts "#{kernelspec_file} already exists!\nUse --force to force a register."
        exit 1
      end
      register_kernel(force)
    when "unregister"
      unregister_kernel
    when "kernel"
      start_kernel
    when "version", "--version", "-v"
      puts "ICrystal #{VERSION}, #{Crystal::DESCRIPTION}"
    else
      puts USAGE
    end
  end

  KERNEL_BANNER = <<-USAGE
    Usage: icrystal kernel [options] config_file

    Options:
    USAGE

  def start_kernel
    OptionParser.parse(options) do |opts|
      opts.banner = KERNEL_BANNER

      opts.on("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      opts.on("-v", "--verbose", "Display verbose information") do
        ENV["CRYSTAL_LOG_LEVEL"] = "DEBUG"
      end
    end

    Log.setup_from_env
    config_file = options[1]?
    Kernel.new(config_file).run
  end

  def kernelspec_dir
    if ENV.has_key?("JUPYTER_DATA_DIR")
      jupyter_data_dir = ENV["JUPYTER_DATA_DIR"]
      File.join(jupyter_data_dir, "kernels", "crystal")
    else
      File.join(Jupyter.kernelspec_dir, "crystal")
    end
  end

  def kernelspec_file
    File.join(kernelspec_dir, "kernel.json")
  end

  def registered_icrystal_path
    file = kernelspec_file
    File.exists?(file) && JSON.parse(File.read(file))["argv"][0]
  end

  def register_kernel(force)
    unregister_kernel if force

    dest_dir = kernelspec_dir
    file = kernelspec_file

    FileUtils.mkdir_p(dest_dir)

    File.write(file, {
      "argv"         => [File.expand_path(PROGRAM_NAME, home: Path.home), "kernel", "{connection_file}"],
      "display_name" => "Crystal #{Crystal::VERSION}",
      "language"     => "crystal",
    }.to_json)

    here = File.dirname(File.real_path(__FILE__))
    FileUtils.cp(Dir[File.join(here, "assets", "*")], dest_dir)

    puts "Registered ICrystal at #{dest_dir}"
  end

  def unregister_kernel
    dir = kernelspec_dir
    FileUtils.rm_rf(dir)
    puts "Unregistered ICrystal from #{dir}"
  end
end
