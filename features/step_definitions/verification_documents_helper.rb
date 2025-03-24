# frozen_string_literal: true

# Helper class which contains methods to verify the content of the document detail section for given verification types on the verification detail page.
class VerificationDocumentsHelper

  class << self
    def verify_content_for(type, page)
      case type
      when "Citizenship"
        expected_content = citizenship_content
      when "Immigration Status"
        expected_content = immigration_status_content
      when "Social Security Number"
        expected_content = ssn_content
      when "Alive Status"
        expected_content = alive_status_content
      when "Coverage from a job"
        expected_content = esi_content
      when "Coverage from MaineCare"
        expected_content = local_mec_content
      when "Coverage from another program"
        expected_content = non_esi_content
      when "Income"
        expected_content = income_content
      else
        false
      end

      verify_all_content(page, expected_content)
    end

    private

    def verify_all_content(page, expected_content)
      expected_content.each do |expected_line|
        if expected_line.is_a?(Hash) && expected_line.key?(:a)
          link_text = expected_line.delete(:a)
          return false unless page.has_link?(link_text, **expected_line)
        else
          return false unless page.has_text?(expected_line)
        end
      end
      true
    end

    def informational_sheet_anchor_hash
      {:a => "Documents Needed for Verification", :href => "https://www.dchealthlink.com/submit-docs"}
    end

    def citizenship_content
      [
        # Preface and main introduction
        "We use electronic data sources to verify citizenship information on your application. If the data sources do not match the information you provided, you will need to provide proof from the list below.",
        "For a full listing of documents you can submit to verify your citizenship, see the",
        informational_sheet_anchor_hash,
        "informational sheet on CoverME.gov.",
        "Documents we accept to confirm your United States (U.S.) citizenship (only need to submit one).",

        # Primary document types
        "U.S. passport",
        "Certificate of Naturalization (N-550/N-570)",
        "Certificate of Citizenship (N-560/N-561)",
        "Consular Report of Birth Abroad of U.S. Citizen (FS-240, CRBA)",
        "State-issued enhanced driver's license (available in Michigan, New York, Vermont, and Washington)",

        # Tribal document section
        "Document from federally recognized Indian tribe",
        "that includes your name and the name of the federally recognized Indian tribe that issued the document",
        "A tribal enrollment card",
        "A Certificate of Degree of Indian Blood",
        "A tribal census document",
        "Documents on tribal letterhead signed by a tribal official",

        # Two-document section
        "If you don't have any of the documents above, you can submit 2 documents – one from each list below.",

        # List 1
        "Submit one of these documents:",
        "U.S. public birth certificate",
        "Consular Report of Birth Abroad of U.S. Citizen (FS-240, CRBA)",
        "Certification of Report of Birth (DS-1350)",
        "Certification of Birth Abroad (FS-545)",
        "U.S. Citizen Identification Card (I-197)",
        "Northern Mariana Card (I-873)",
        "Final adoption decree showing name and U.S. place of birth",
        "Military record showing a place of U.S. birth",

        # List 2
        "AND",
        "one of these documents",
        "Driver's license issued by a state or territory or ID card issued by the federal, state, or local government",
        "School identification card",
        "U.S. military card or draft record",
        "Military dependent's identification card",
        "U.S. Coast Guard Merchant Mariner card",
        "Voter registration card"
      ]
    end

    def immigration_status_content
      [
        # Preface and main introduction
        "We use electronic data sources to verify immigration information provided on your application. If the data sources do not match the information you provided, you will need to provide documents to confirm your immigration status.",
        "For a full listing of documents you can submit to verify your immigration status, see the",
        informational_sheet_anchor_hash,
        "informational sheet on CoverME.gov.",

        # Heading
        "Documents we accept as proof of",
        "immigration:",

        # Document types
        "Permanent Resident Card, \"Green Card\" (I-551)",
        "Reentry Permit (I-327)",
        "Refugee Travel Document (I-571)",
        "Employment Authorization Card (I-766)",
        "Machine Readable Immigrant Visa (with temporary I-551 language)",
        "Temporary I-551 Stamp (on Passport or I-94/I-94A)",
        "Foreign passport",
        "Arrival/Departure Record (I-94/I-94A)",
        "Arrival/Departure Record in foreign passport (I-94)",
        "Certificate of Eligibility for Nonimmigrant Student Status (I-20)",
        "Certificate of Eligibility for Exchange Visitor Status (DS-2019)",
        "Notice of Action (I-797)",
        "Document indicating a member of a federally recognized Indian tribe or American Indian born in Canada",
        "Certification from U.S. Department of Health and Human Services (HHS) Office of Refugee Resettlement (ORR)",
        "Document indicating withholding of removal (or withholding of deportation)",
        "Office of Refugee Resettlement (ORR) eligibility letter (if under 18)",
        "USCIS Acknowledgement of Receipt (I-797C)"
      ]
    end

    def identity_content
      [
        # Preface and main introduction
        "We use electronic data sources to verify your identity. If the data sources do not match the information you gave us, you will need to provide proof from the list below.",
        "For a full listing of documents you can submit to verify your identity, see the",
        informational_sheet_anchor_hash,
        "informational sheet on CoverME.gov.",

        # Heading
        "Documents we accept as proof of identity:",

        # Primary document types
        "Driver's license issued by state or territory",
        "School identification card",
        "Voter registration card",
        "U.S. Military card or draft record",
        "Military dependent's identification card",
        "Identification card issued by the federal, state, or local government",
        "Certificate of Naturalization (Form N-550 or N-570)",
        "Certificate of U.S. Citizenship (Form N-560 or N-561)",
        "Permanent Resident Care or Alien Registration Receipt Care (Form I-551)",
        "Employment Authorization Document that contains a photograph (Form I-766)",
        "U.S. passport or U.S. passport card",
        "Native American tribal document",
        "U.S. Coast Guard Merchant Mariner card",
        "Foreign passport, or identification card issued by a foreign embassy or consulate that contains a photograph",

        # Two-document section
        "If you don't have an of the documents above, you can submit 2 of these documents (names must match):",
        "U.S. public birth certificate",
        "Social Security card",
        "Marriage certificate",
        "Divorce decree",
        "Employer Identification Card",
        "High school or college diploma (including high school equivalency diplomas)",
        "Property deed or title (including for a vehicle)"
      ]
    end

    def ssn_content
      [
        # Preface
        "We use electronic data sources to verify the Social Security numbers (SSNs) provided. If the data sources do not match the information you gave us, you will need to provide at least one of the documents from the list below.",

        # Heading
        "Documents we accept for proof of Social Security numbers. All documents must include your first name, last name, and SSN.",

        # Document types
        "Social Security card",
        "1040 Tax Return",
        "W-2 and/or 1099's (includes 1099 MISC, 1099G, 1099R, 1099SSA, 1099DIV, 1099S, 1099INT)",
        "W-4 Withholding Allowance Certificate",
        "1095 (includes 1095-A, 1095-B, 1095-C)",
        "Pay stub",
        "Social Security Administration documentation (includes 4029)",
        "Military record",
        "U.S. Military ID card",
        "Military dependent's ID card",
        "Unemployment benefits letter",
        "Court order granting a name change (must contain your original first and last name, your new first and last name, and SSN)",
        "Divorce decree"
      ]
    end

    def alive_status_content
      [
        "We use electronic data sources to confirm consumers enrolled in coverage have not passed away. Our records show that this member has passed away.  If this information is correct, their coverage will end soon.",
        "If this information is incorrect or there are household members who will need to continue coverage, call the CoverME.gov Consumer Assistance Center at 1-866-636-0355."
      ]
    end

    def esi_content
      [
        "Documents we accept as proof that job-based coverage is not qualifying health coverage:",
        "Cover letter from employer coverage tool",
        "Letter or other documentation from an employer or other documentation with the following information:",
        "Statement that the employer doesn't currently offer you (or your family member) coverage",
        "Statement that the employer doesn't provide coverage that meets the minimum value standard",
        "Statement showing the cost of your share of the premium for the lowest-cost self-only plan that meets the minimum value standard, is offered.",
        "Health insurance letter that contains confirmation of health coverage and expiration dates for coverage"
      ]
    end

    def non_esi_content
      [
        "Our records indicate you may have other health insurance coverage that meets Affordable Care Act (ACA) standards (such as Medicare, TRICARE, Veteran's health coverage). Individuals who are enrolled or have access to other coverage are not" \
        " eligible to enroll with financial assistance on CoverME.gov.",
        "If you have Medicare or other coverage, it is important to end this person's CoverME.gov coverage as soon as possible to avoid needing to pay back all or some of the premium tax credits you received.",
        "If you aren’t eligible or enrolled in other coverage, you need to provide documents to confirm you do not have coverage from another program.",
        "For a full listing of documents you can submit to verify you don’t have other health coverage, see the",
        informational_sheet_anchor_hash,
        "informational sheet on CoverME.gov.",
        "Documents we accept to confirm you don't have qualifying health coverage through Medicare:",
        "Letter or statement from Medicare or the Social Security Administration stating that you or your family members are:",
        "Not eligible for or enrolled in premium-free Medicare Part A.",
        "Eligible for (but not enrolled in) Part A coverage that requires premium payments.",
        "No longer eligible for Social Security Disability insurance (SSDI) benefits, and your coverage has ended or will end in the next 90 days.",
        "Documents we accept as proof you don't have other health coverage:",
        "Letter or statement from the Veterans Administration",
        "Letter or statement from TRICARE",
        "Letter or statement from Peace Corps"
      ]
    end

    def local_mec_content
      [
        "Our records indicate you may be enrolled in MaineCare (Medicaid). Individuals who are enrolled in MaineCare are not eligible to enroll with financial assistance on CoverME.gov.",
        "If you are enrolled in MaineCare, you should end your coverage with CoverME.gov.",
        "If you aren't sure if you are enrolled in or if you have been determined eligible for MaineCare, contact the Office for Family Independence at 1-855-797-4357 to verify your enrollment status.",
        "If you aren't enrolled in MaineCare or are only enrolled in limited benefits (such as MaineCare that only covers emergency treatment or family planning services), you need to provide documents to confirm you do not qualify for" \
        " full-benefit coverage through MaineCare.",
        "For a full listing of documents you can submit, see the",
        informational_sheet_anchor_hash,
        "informational sheet on CoverME.gov.",
        "Documents we accept to confirm that you don't have coverage through MaineCare (Medicaid):",
        "Letter or statement from the MaineCare agency that shows you or your family members aren't enrolled in or eligible for MaineCare.",
        "Letter or statement from the MaineCare agency showing that you are enrolled in a MaineCare limited benefit program that's not considered qualifying health coverage.",
        "A letter or statement from the MaineCare agency showing when your coverage ended or that you were never enrolled in MaineCare coverage."
      ]
    end

    def income_content
      [
        "We use electronic data sources to verify the income information you provided on your application. It is important to ensure the information is accurate since any financial savings you may receive will need to be reconciled when you file" \
        " your taxes. If the data sources do not match the information on your application, you will need to provide at least one of the documents from the list below. For a full listing of documents you can submit to verify your income, see the",
        informational_sheet_anchor_hash,
        "informational sheet on CoverME.gov.",
        "Documents we accept as proof of earned income:",
        "Most recently filed Federal Income Tax Form 1040, with appropriate Schedules. Must contain first and last name, income amount, and tax year.",
        "Pay stubs: Must contain first and last name or other identifying information (e.g., SSN), income amount, and pay period or frequency of pay with the date of payment.",
        "Wages and tax statement (W-2 and/or 1099, including 1099 MISC, 1099G, 1099R, 1099SSA, 1099 DIV, 1099SS, 1099INT). Must contain first and last name, income amount, tax year, and employer name (if applicable).",
        "Employer Statement. Must be on company letterhead or state the name of the company, employer contact information, signed by the employer, be no older than 45 days from the date received by CoverME.gov, and verify the start or end date of" \
        " employment and pay amount.",
        "Documents we accept as proof of self-employment:",
        "Federal Income Tax Return, with appropriate Schedules. Must contain first and last name, income amount, and tax year.",
        "Self-employment ledger documentation (can be a Schedule C, the most recent quarterly or year-to-date profit and loss statement, or a self-employment ledger). Must contain first and last name, company name, and income amount. If submitting" \
        " self-employment ledger, include the dates covered by the ledger, and the net income from profit/loss.",
        "Documents we accept for other types of income:",
        "Social Security Administration Statements (Social Security Benefits Letter)",
        "Unemployment Benefits Letter. Must contain first and last name, source/agency, benefits amount, and duration (start and end date, if applicable).",
        "Award letters or distribution statements such as annuity statements, pension distribution from any government or private source. Must contain first and last name, source, income amount, and frequency.",
        "Worker's compensation letter",
        "Prizes, settlements, and awards, including court-ordered awards letter",
        "Proof of gifts and contributions",
        "Proof of inheritances in cash or property",
        "Interests and dividends income statement"
      ]
    end
  end
end
