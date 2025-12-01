# frozen_string_literal: true

require "csv"
require File.join(Rails.root, "lib/mongoid_migration_task")

# rake to delete duplicate family members
class RemoveDuplicateFamilyMembers < MongoidMigrationTask
  def parse_csv_ids(csv_string)
    return [] if csv_string.blank?

    csv_string.split(",")
              .map(&:strip)
              .reject(&:blank?)
  end

  def parse_ids_from_csv(path)
    return [] if path.blank?
    raise ArgumentError, "CSV file not found: #{path}" unless File.exist?(path)

    csv = CSV.read(path, headers: true)
    headers = csv.headers.compact.map(&:downcase)

    ids = if headers.include?("hbx_id")
            extract_ids_from_header_csv(csv)
          else
            extract_ids_from_headerless_csv(path)
          end

    ids.uniq
  end

  # Must accept csv_file because specs call migrate(nil, csv_file)
  def migrate(hbx_ids_csv = nil, csv_file = nil)
    hbx_ids = collect_hbx_ids(hbx_ids_csv, csv_file)
    raise ArgumentError, "No valid HBX IDs found in the input." if hbx_ids.empty?

    stats = initialize_stats

    begin
      hbx_ids.each { |id| process_hbx_id(id, stats) }
    rescue StandardError => e
      puts "Unexpected Error: #{e.message}"
    end

    print_summary(stats)
  end

  private

  def extract_ids_from_header_csv(csv)
    csv.each_with_object([]) do |row, ids|
      val = row["hbx_id"] || row[row.headers.find { |h| h&.downcase == "hbx_id" }]
      ids << val.to_s.strip if val.present?
    end
  end

  def extract_ids_from_headerless_csv(path)
    CSV.foreach(path, headers: false).each_with_object([]) do |row, ids|
      next if row[0].blank?
      ids << row[0].to_s.strip
    end
  end

  # Supports both ENV["csv"] and ENV["csv_file"] (required by specs)
  def collect_hbx_ids(hbx_ids_csv, csv_file)
    inline_ids = parse_csv_ids(hbx_ids_csv || ENV["hbx_ids"])
    file_path = csv_file || ENV["csv_file"] || ENV["csv"]

    file_ids = parse_ids_from_csv(file_path)
    (inline_ids + file_ids).uniq
  end

  def initialize_stats
    {
      processed: 0,
      people_found: 0,
      families_with_duplicates: 0,
      duplicates_removed: 0
    }
  end

  def process_hbx_id(hbx_id, stats)
    stats[:processed] += 1
    person = Person.where(hbx_id: hbx_id).first

    return puts("No Person found for HBX ID: #{hbx_id}") unless person

    stats[:people_found] += 1
    process_person_family(person, stats)
  end

  def process_person_family(person, stats)
    family = person.primary_family
    return puts("No primary family found for Person #{person.id}") unless family

    duplicates = find_duplicate_family_members(family)
    return puts("No duplicates for family #{family.id}") if duplicates.empty?

    stats[:families_with_duplicates] += 1
    remove_duplicates(duplicates, stats)
  end

  def find_duplicate_family_members(family)
    family.family_members
          .group_by(&:person_id)
          .select { |_pid, members| members.size > 1 }
  end

  def remove_duplicates(duplicate_groups, stats)
    duplicate_groups.each_value do |members|
      sorted = members.sort_by(&:created_at)
      member_to_remove = sorted.last

      begin
        member_to_remove.destroy
        stats[:duplicates_removed] += 1
        puts "Removed duplicate family_member #{member_to_remove.id}"
      rescue StandardError => e
        puts "Error removing member #{member_to_remove.id}: #{e.message}"
      end
    end
  end

  def print_summary(stats)
    puts "========== SUMMARY =========="
    puts "HBX IDs processed: #{stats[:processed]}"
    puts "People found: #{stats[:people_found]}"
    puts "Families with duplicates: #{stats[:families_with_duplicates]}"
    puts "Duplicates removed: #{stats[:duplicates_removed]}"
    puts "============================="
  end
end
