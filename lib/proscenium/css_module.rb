# frozen_string_literal: true

class Proscenium::CssModule
  def initialize(path)
    @path = "#{path}.module.css"

    Proscenium::SideLoad.append! Rails.root.join(@path)
  end

  # Returns an Array of class names generated from the given CSS module `names`.
  def class_names(*names)
    names.flatten.compact.map { |name| "#{name}#{hash}" }
  end

  private

  def hash
    @hash ||= Digest::SHA1.hexdigest("/#{@path}")[..7]
  end
end
