class Proscenium::CssModule
  def initialize(path)
    @path = path

    Proscenium::SideLoad.append path, :cssm
  end

  # Returns an Array of class names generated from the given CSS module `names`.
  def class_names(*names)
    names.flatten.compact.map do |name|
      "#{name}#{Digest::SHA1.hexdigest("/#{@path}.css|#{name}")[0, 8]}"
    end
  end
end
