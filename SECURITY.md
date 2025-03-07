# Security Policy

## Vulnerability Mitigations

### CVE-2024-21510 - Sinatra

**Vulnerability:** Sinatra vulnerable to Reliance on Untrusted Inputs in a Security Decision

**Mitigation:** This vulnerability affects Sinatra when used for parsing HTTP requests. In our application, Sinatra is not directly used for this purpose. It is a dependency of Resque, which we use for background job processing. The vulnerable component of Sinatra is not exercised in our usage context, therefore the risk is minimal.

**Actions Taken:**
1. We have documented this issue and our mitigation strategy.
2. We are monitoring for updates to Resque that might include a patched version of Sinatra.
3. We have verified that our usage of Resque does not expose Sinatra to untrusted input in our application setup.
4. We have configured bundler-audit to ignore this specific vulnerability in our CI/CD pipeline.

**Ongoing Measures:**
1. Regular review of dependencies and their security advisories.
2. Periodic assessment of our usage of Resque to ensure it remains unexposed to the vulnerable Sinatra components.

### Advisory GHSA-vfm5-rmrh-j26v - Action Dispatch 2024-12-10

**Vulnerability:**

Source: https://github.com/rails/rails/security/advisories/GHSA-vfm5-rmrh-j26v

NVD: https://nvd.nist.gov/vuln/detail/CVE-2024-54133

There is a possible Cross Site Scripting (XSS) vulnerability in the content_security_policy helper in Action Pack.

Applications which set Content-Security-Policy (CSP) headers dynamically from untrusted user input may be vulnerable to carefully crafted inputs being able to inject new directives into the CSP. This could lead to a bypass of the CSP and its protection against XSS and other attacks.

**Mitigation:**

No mitigation required as we are not vulnerable.

We do not dynamically set our CSP values using user input.

This specific security advisory has been added to the bundler audit ignore file.

### Advisory GHSA-vvfq-8hwr-qm4m - Nokogiri 2025-02-18

#### Vulnerability

Source: https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-vvfq-8hwr-qm4m

This advisory addresses two separate vulnerabilities:
1. CVE-2025-24928
2. CVE-2024-56171

These vulnerabilities are present in the underlying `libxml2` implementation packaged with Nokogiri versions `< 1.18.3`.

#### CVE-2025-24928

NVD: https://nvd.nist.gov/vuln/detail/CVE-2025-24928

Source: https://gitlab.gnome.org/GNOME/libxml2/-/issues/847

**Description:**

```
libxml2 before 2.12.10 and 2.13.x before 2.13.6 has a stack-based buffer overflow in xmlSnprintfElements in valid.c. To exploit this, DTD validation must occur for an untrusted document or untrusted DTD. NOTE: this is similar to CVE-2017-9047.
```

Notes from the libxml2 bugtracker state:

```
This issue only affects DTD validation of untrusted XML documents or validation against untrusted DTDs. It can be triggered by passing the XML_PARSE_DTDVALID parser option or by calling one of the DTD validation functions like xmlValidateDocument or xmlValidateDtd.
```

**Mitigation:**

There are few endpoints in Enroll which accept XML data.  Of those, none perform DTD validation.  As explotation requires the execution of DTD validation against a crafted XML document, Enroll is not considered vulnerable.

#### CVE-2024-56171

NVD: https://nvd.nist.gov/vuln/detail/CVE-2024-56171

Source: https://gitlab.gnome.org/GNOME/libxml2/-/issues/828

**Description:**

```
libxml2 before 2.12.10 and 2.13.x before 2.13.6 has a use-after-free in xmlSchemaIDCFillNodeTables and xmlSchemaBubbleIDCNodeTables in xmlschemas.c. To exploit this, a crafted XML document must be validated against an XML schema with certain identity constraints, or a crafted XML schema must be used.
```

Notes from the libxml2 bugtracker state:

```
This issue affects validation against untrusted XML Schemas (.xsd) and, potentially, validation of untrusted documents against trusted Schemas if they make use of xsd:keyref in combination with recursively defined types that have additional identity constraints. It's hard for me to judge whether this is common in practice.
```

**Mitigation:**

There are few endpoints in Enroll which accept XML data.  Of those, none perform validation using an XML schema which contains usage of the xsd:keyref construct.  As explotation requires these conditions, Enroll is not considered vulnerable.

#### Actions Taken

Given that Enroll is not considered vulnerable against either underlying CVE, this specific security advisory has been added to the bundler audit ignore file.


### CVE-2025-27111 - Rack

Issue:  https://github.com/rack/rack/security/advisories/GHSA-8cgq-6mh2-7j6v

Source: https://gitlab.gnome.org/GNOME/libxml2/-/issues/828

Summary: Rack::Sendfile can be exploited by crafting input that includes newline characters to manipulate log entries.

Description: Rack versions before 2.2.12, 3.0.13, and 3.1.11 contain an escape sequence injection vulnerability that may allow an attacker to inject malicious characters into log files. This could lead to log manipulation or, in some cases, remote code execution depending on log processing mechanisms.

**Vulnerability:**

Escape Sequence Injection vulnerability in Rack lead to Possible Log Injection

**Mitigation:**

Enroll does not log untrusted user inputs in a way that could be exploited by this vulnerability. We are not sending any sensitive information via logging mechanism from our system. Additionally, there are no known attack vectors where an attacker could inject escape sequences that would result in a security risk. We are not using any Rack::Sendfile.

**Actions Taken:**

1. Reviewed logging mechanisms to ensure no exposure to this vulnerability.
2. Added GHSA-8cgq-6mh2-7j6v to the Bundler audit ignore file.
3. Verified Usage of Rack::Sendfile on our repo.


**Ongoing Measures:**
1. Regular review of dependencies and their security advisories.


### Advisory GHSA-r95h-9x8f-r3f7 - Nokogiri 2025-03-07

#### Vulnerability

Source: https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-r95h-9x8f-r3f7

This advisory addresses this vulnerabilities:
1. CVE-2024-34459

These vulnerabilities are present in the underlying `libxml2` implementation packaged with Nokogiri versions `< 1.18.3`.

#### CVE-2024-34459

Source: https://gitlab.gnome.org/GNOME/libxml2/-/commit/2876ac53

**Description:**

```
Nokogiri v1.16.5 upgrades its dependency libxml2 to 2.12.7 from 2.12.6. This issue is happening with libxml2's xmllint tool.
```

Notes from the libxml2 bugtracker state:

```
There is no impact to Nokogiri users because the issue is present only in libxml2's xmllint tool which Nokogiri does not provide or expose.
```

**Mitigation:**

this a low severity issue as it only affects the rarely used --htmlout option of xmllint. We are not using this on our system.

#### Actions Taken

Given that Enroll is not considered vulnerable against either underlying CVE, this specific security advisory has been added to the bundler audit ignore file.
