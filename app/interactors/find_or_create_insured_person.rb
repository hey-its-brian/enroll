class FindOrCreateInsuredPerson
  include Interactor

  def call
    user = context.user
    people = match_person

    person, is_new = nil, nil
    case people.count
    when 1
      person = people.first
      user.save if user
      person.user = user if user
      if person.ssn.nil?
        #matched on last_name and dob
        person.ssn = context.ssn
        person.gender = context.gender
        person.no_ssn = context.no_ssn
      end
      set_person_emails(person, user)
      person.save
      user = person.user if context.role_type == User::ROLES[:consumer]
      person, is_new = person, false
    when 0
      return if context.ssn.present? && Person.where(encrypted_ssn: Person.encrypt_ssn(context.ssn)).present?
      if user.try(:person).try(:present?)
        if (user.person.first_name.downcase == context.first_name.downcase) &&
           (user.person.last_name.downcase == context.last_name.downcase) # if user enters lowercase during matching.
          person = user.person
          person.assign_attributes(name_sfx: context.name_sfx,
                                   middle_name: context.middle_name,
                                   name_pfx: context.name_pfx,
                                   ssn: context.ssn,
                                   dob: context.dob,
                                   gender: context.gender,
                                   no_ssn: context.no_ssn)
          set_person_emails(person, user)
          person.save
          is_new = false
        else
          context.person = nil
          context.is_new = nil
          return
        end
      else
        person = Person.new(
          user: user,
          name_pfx: context.name_pfx,
          first_name: context.first_name,
          middle_name: context.middle_name,
          last_name: context.last_name,
          name_sfx: context.name_sfx,
          ssn: context.ssn,
          no_ssn: context.no_ssn,
          dob: context.dob,
          gender: context.gender
        )
        set_person_emails(person, user)
        person.save
        if person.persisted?
          is_new = true
        else
          context.person = nil
          context.is_new = nil
          return
        end
      end
    else
      # what am I doing here?  More than one person had the same SSN?
      context.person = nil
      context.is_new = nil
      return
    end

    if user.present?
      user.roles << context.role_type unless user.roles.include?(context.role_type)
      user.save
    end
    context.person = person
    context.is_new = is_new
  end

  private

  def set_person_emails(person, user)
    return unless user
    return if person.emails.any? || user.email.blank?

    person.emails.build(kind: "home", address: user.email)
  end

  def match_person
    raise ArgumentError, "must provide an ssn or first_name/last_name/dob or both" if context.ssn.blank? && (context.dob.blank? || context.last_name.blank? || context.first_name.blank?)

    _query_criteria, people = Operations::People::Match.new.call({:dob => context.dob,
                                                                  :last_name => context.last_name,
                                                                  :first_name => context.first_name,
                                                                  :ssn => context.ssn})

    people.to_a
  end
end
