require File.join(Rails.root, "app", "data_migrations", "update_negative_response_received_evidences")

namespace :migrations do
  desc "update_negative_response_received_evidences"
  UpdateNegativeResponseReceivedEvidences.define_task :update_negative_response_received_evidences => :environment
end