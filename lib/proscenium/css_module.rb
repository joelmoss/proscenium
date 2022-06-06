# frozen_string_literal: true

class Proscenium::CssModule
  def initialize(path)
    @path = Rails.root.join("#{path}.module.css")

    Proscenium::SideLoad.append! @path
  end

  # Returns an Array of class names generated from the given CSS module `names`.
  def class_names(*names)
    names.flatten.compact.map { |name| "#{name}#{hash}" }
  end

  private

  def hash
    @hash ||= Digest::MD5.file(@path).hexdigest[..7]
  end
end
