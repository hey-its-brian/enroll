class Inbox
  include Mongoid::Document

  field :access_key, type: String

  # Enable polymorphic associations
  embedded_in :recipient, polymorphic: true
  embeds_many :messages
  accepts_nested_attributes_for :messages

  before_create :generate_acccess_key

  after_save :maybe_notify_received_message

  def read_messages
    messages.where(message_read: true, folder: Message::FOLDER_TYPES[:inbox])
  end

  def unread_messages
    messages.where(message_read: false, folder: Message::FOLDER_TYPES[:inbox]) +
    messages.where(message_read: false, folder: nil)
  end

  def post_message(new_message)
    self.messages.push new_message
    self
  end

  def delete_message(message)
    return self if self.messages.size == 0
    message = self.messages.detect { |m| m.id == message.id }
    message.delete unless message.nil?
    self
  end

  def maybe_notify_received_message
    return unless @message_received && recipient.is_a?(Person)

    notification_event = event(
      "enroll.people.person_inbox_message_received",
      attributes: {
        person_id: recipient.id
      }
    )
    notification_event.success.publish
  end

private
  def generate_acccess_key
    self.access_key = [id.to_s, SecureRandom.hex(10)].join
  end
end
