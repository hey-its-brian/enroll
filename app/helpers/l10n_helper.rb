# frozen_string_literal: true

require 'html_scrubber_util'

# Helper methods for localization with interpolation
module L10nHelper
  include ActionView::Helpers::TranslationHelper
  include HtmlScrubberUtil

  # @note Due to a caching issue in Rails 6.1, the `MISSING_TRANSLATION` object from
  #   `ActionView::Helpers::TranslationHelper` is cached in the I18n cache and read back as a
  #   different object. This issue occurs when calling `t(translation_key, default: translation_key.to_s&.gsub(/\W+/, '')&.titleize)`
  #   twice, where the value is returned back as a different object the second time. This issue might be fixed in Rails 7.0.4.
  #   Using `I18n.t` instead of `t` can lead to issues related to short naming of the translation key like l10n('.welcome_to_site_sub_header').
  #   Therefore, we are using `t` method with `raise: true` option to avoid the caching issue and returning the titleized translation key if the translation is missing.
  def l10n(translation_key, interpolated_keys = {})
    result = fetch_translation(translation_key.to_s, interpolated_keys)

    sanitize_result(result, translation_key)
  rescue I18n::MissingTranslationData, RuntimeError => e
    handle_missing_translation(translation_key, e)
  end

  private

  def fetch_translation(translation_key, interpolated_keys)
    options = interpolated_keys.present? ? interpolated_keys.merge(default: default_translation(translation_key)) : {}

    t(translation_key, **options, raise: true)
  rescue I18n::MissingInterpolationArgument => e
    handle_missing_interpolation_argument(translation_key, interpolated_keys, e)
  end

  def sanitize_result(result, translation_key)
    return translation_key.to_s unless result.respond_to?(:html_safe)

    sanitize_html(result)
  end

  def handle_missing_translation(translation_key, error)
    Rails.logger.error {"#L10nHelper missing translation for key: #{translation_key}, error: #{error.inspect}"}

    sanitize_result(default_translation(translation_key), translation_key)
  end

  def handle_missing_interpolation_argument(translation_key, interpolated_keys, error)
    Rails.logger.error {"#L10nHelper missing interpolation argument for key: #{translation_key}, provided keys: #{interpolated_keys.keys}, error: #{error.inspect}"}

    missing_key = error.message.match(/missing interpolation argument :(\w+)/i)&.captures&.first

    fallback_keys = interpolated_keys.dup
    fallback_keys[missing_key.to_sym] = "[#{missing_key}]" if missing_key

    begin
      options = fallback_keys.merge(default: default_translation(translation_key))
      t(translation_key, **options, raise: true)
    rescue I18n::MissingInterpolationArgument, I18n::MissingTranslationData => e
      Rails.logger.error {"#L10nHelper fallback also failed for key: #{translation_key}, error: #{e.inspect}"}
      default_translation(translation_key)
    end
  end

  def default_translation(translation_key)
    translation_key.to_s&.gsub(/\W+/, '')&.titleize
  end
end
