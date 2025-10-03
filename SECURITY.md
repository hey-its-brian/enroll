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

#### CVE-2025-55193

Source: https://github.com/rails/rails/security/advisories/GHSA-76r7-hhxj-r776

**Description:**

```
A possible ANSI escape injection in Active Record logging could allow crafted values to inject control sequences into logs/terminals (e.g., colored output, cursor movement).
```

**Mitigation:**
We backported the upstream fix by ensuring ActiveRecord::RecordNotFound messages render identifiers via .inspect, neutralizing control characters. We also reduced exposure by disabling verbose/colorized SQL logs.

**Actions Taken**

1. Added initializer backport: config/initializers/security_backports/activerecord_record_not_found_escape.rb (from Rails upstream behavior).
2. Set conservative logging defaults (disable verbose query logs/colorized logs).
3. Documented the issue and added GHSA-76r7-hhxj-r776 to .bundler-audit.yml temporarily, pending framework upgrade.

**TODO - Future Actions**
1. When we upgrade Rails Version to ~> 7.1.5.2', '~> 7.2.2.2', '>= 8.0.2.1', we need to remove 
config/initializers/security_backports/activerecord_record_not_found_escape.rb


#### CVE-2025-24293

Source: https://github.com/rails/rails/security/advisories/GHSA-r4mg-4433-c7g3

**Description:**

```
Active Storage allowed transformation methods that were potentially unsafe (e.g., passing through options that could be abused when user-controlled).
```

**Mitigation:**
We backported the upstream restriction that disallows the dangerous transformation keys (:apply, :loader, :saver) so they cannot be used in variants.

**Actions Taken**

1. Added initializer backport: config/initializers/security_backports/active_storage_disallow_dangerous_transformations.rb (blocks :apply, :loader, :saver).
2. Verified our code serves only whitelisted server-side variants and does not accept user-supplied transform options.
3. Documented the issue and added GHSA-r4mg-4433-c7g3 to .bundler-audit.yml temporarily, pending framework upgrade.

**TODO - Future Actions**
1. When we upgrade Rails Version to ~> 7.1.5.2', '~> 7.2.2.2', '>= 8.0.2.1', we need to remove 
config/initializers/security_backports/active_storage_disallow_dangerous_transformations.rb

### CVE-2023-4771, CVE-2024-24815, CVE-2024-24816, CVE-2024-43407, CVE-2024-43411

**Sources:**
- https://github.com/ckeditor/ckeditor4/security/advisories/GHSA-wh5w-82f3-wrxh
- https://github.com/ckeditor/ckeditor4/security/advisories/GHSA-fq6h-4g8v-qqvm
- https://github.com/ckeditor/ckeditor4/security/advisories/GHSA-mw2c-vx6j-mg76
- https://github.com/ckeditor/ckeditor4/security/advisories/GHSA-7r32-vfj5-c2jv
- https://github.com/ckeditor/ckeditor4/security/advisories/GHSA-6v96-m24v-f58j

**Description:**

These vulnerabilities affect CKEditor 4 demo/sample files and plugins that are not deployed in production:

1. **CVE-2023-4771**: XSS vulnerability in the AJAX sample file
2. **CVE-2024-24815**: XSS vulnerability in CDATA detection (affects samples)
3. **CVE-2024-24816**: XSS vulnerability in samples using the preview feature
4. **CVE-2024-43407**: Reflected XSS in Code Snippet GeSHi plugin
5. **CVE-2024-43411**: Low-risk XSS linked to potential domain takeover

All vulnerabilities are in sample/demo files or optional plugins that are not included in our production deployment.

**Risk Assessment:**
- **Severity**: Low to Medium (in isolation)
- **Actual Risk**: Minimal - vulnerable code paths are not present in production
- **Impact**: No production functionality uses the affected samples or plugins

**Mitigation:**

1. **Verified non-exposure**: Confirmed that our application does not:
   - Deploy CKEditor sample files to production
   - Use the AJAX sample functionality
   - Use the Code Snippet GeSHi plugin

2. **Access controls**: CKEditor is only accessible to authenticated, authorized users (not public-facing)

3. **Input sanitization**: All user-generated content is sanitized server-side before storage and display

4. **Content Security Policy**: Implemented CSP headers to mitigate XSS impact

**Actions Taken:**

1. Upgraded CKEditor from 4.2.4 to 5.1.3 (resolved 10 high/medium severity vulnerabilities)
2. Audited production CKEditor configuration to confirm no sample files are deployed
3. Verified GeSHi plugin is not installed or enabled
4. Documented vulnerabilities and added to `.bundler-audit.yml` ignore list
5. Implemented server-side content sanitization for all rich text fields

**Monitoring:**
- Regularly check for CKEditor security updates
- Monitor for patches addressing these specific CVEs
- Review CKEditor configuration during security audits

**TODO - Future Actions:**

1. **When patches become available**: Upgrade to patched version and remove CVEs from `.bundler-audit.yml`
2. **Consider migration**: Evaluate migrating to CKEditor 5 (complete rewrite with better security model) or alternative editors (Trix, Quill, TipTap)