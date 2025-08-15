# frozen_string_literal: true

# Backport for GHSA-r4mg-4433-c7g3 / CVE-2025-24293.
# Module used to block unsafe ActiveStorage ImageProcessing transformation keys on Rails 6.1.
module ActiveStorageDangerousTransformationsBlocklist
  def validate_transformation(name, argument)
    if %i[apply loader saver].include?(name.to_sym)
      raise ActiveStorage::Transformers::ImageProcessingTransformer::
            UnsupportedImageProcessingMethod,
            "`#{name}` is not permitted (security backport GHSA-r4mg-4433-c7g3)"
    end
    super(name, argument)
  end
end

ActiveSupport.on_load(:active_storage) do
  next unless defined?(ActiveStorage::Transformers::ImageProcessingTransformer)

  transformer = ActiveStorage::Transformers::ImageProcessingTransformer

  if transformer.method_defined?(:validate_transformation)
    transformer.prepend(ActiveStorageDangerousTransformationsBlocklist)
  else
    # Fallback: sanitize just before processing
    mod = Module.new do
      define_method(:process) do |file, *args|
        sanitized = @transformations.dup
        %i[apply loader saver].each do |k|
          sanitized.delete(k)
          sanitized.delete(k.to_s)
        end
        @transformations = sanitized
        super(file, *args)
      end
    end
    transformer.prepend(mod)
  end
end
