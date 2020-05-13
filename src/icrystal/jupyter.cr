module ICrystal::Jupyter
  extend self

  # See https://jupyter.readthedocs.io/en/latest/projects/jupyter-directories.html
  def default_data_dir
    if macos?
      File.expand_path("~/Library/Jupyter", home: Path.home)
    elsif linux?
      data_home = ENV.fetch("XDG_DATA_HOME", File.expand_path("~/.local/share", home: Path.home))
      File.join(data_home, "jupyter")
    else
      STDERR.puts "windows not supported yet"
      exit 1
    end
  end

  def kernelspec_dir(data_dir = default_data_dir)
    File.join(data_dir, "kernels")
  end

  private def windows?
    false
  end

  private def linux?
    /linux/ =~ Crystal::DESCRIPTION
  end

  private def macos?
    /apple/ =~ Crystal::DESCRIPTION
  end
end
