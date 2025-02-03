# frozen_string_literal: true

module L10nWorld
  include HtmlScrubberUtil
  include ::L10nHelper

  def l10n(translation_key, interpolated_keys = {})
    l10n_result = super(translation_key, interpolated_keys)
    decode_html_entities(l10n_result)
  end

  # @note Due to an issue with how the l10n method sanitizes translation strings, it produces html entities
  # that are not being decoded. This method can be expanded to handle more html entities as needed. Specifically,
  # this causes cucumbers that check page content to fail when the translation content contains html entities.
  def decode_html_entities(result)
    result.gsub(/&amp;/, '&')
  end
end

World(L10nWorld)