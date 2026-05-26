// DetourOpenHumanIntegrationCatalog.swift — OpenHuman integration catalog projection (0.5A)

import Foundation

enum DetourIntegrationCategory: String, Codable, Equatable, Sendable {
    case chat = "Chat"
    case social = "Social"
    case productivity = "Productivity"
    case platform = "Platform"
    case tools = "Tools"
}

struct DetourOpenHumanIntegration: Equatable, Sendable {
    var slug: String
    var name: String
    var category: DetourIntegrationCategory
    var logoURL: URL?

    var candidateID: String {
        switch slug {
        case "twitter":
            return "connector.twitter"
        case "googlecalendar":
            return "connector.google-calendar"
        case "googledocs":
            return "connector.google-docs"
        case "googledrive":
            return "connector.google-drive"
        case "googlesheets":
            return "connector.google-sheets"
        default:
            return "connector.\(slug.replacingOccurrences(of: "_", with: "-"))"
        }
    }
}

enum DetourOpenHumanIntegrationCatalog {
    static let integrations: [DetourOpenHumanIntegration] = rawIntegrations.map { slug, name in
        DetourOpenHumanIntegration(
            slug: slug,
            name: name,
            category: category(slug: slug, name: name),
            logoURL: URL(string: "https://logos.composio.dev/api/\(slug)")
        )
    }

    private static let rawIntegrations: [(String, String)] = [
        ("airtable", "Airtable"), ("apaleo", "Apaleo"), ("asana", "Asana"),
        ("attio", "Attio"), ("basecamp", "Basecamp"), ("bitbucket", "Bitbucket"),
        ("blackbaud", "Blackbaud"), ("boldsign", "Boldsign"), ("box", "Box"),
        ("cal", "Cal"), ("calendly", "Calendly"), ("canva", "Canva"),
        ("capsule_crm", "Capsule CRM"), ("clickup", "ClickUp"),
        ("confluence", "Confluence"), ("contentful", "Contentful"),
        ("convex", "Convex"), ("crowdin", "Crowdin"), ("dart", "Dart"),
        ("dialpad", "Dialpad"), ("digital_ocean", "DigitalOcean"),
        ("discord", "Discord"), ("discordbot", "Discord Bot"),
        ("dropbox", "Dropbox"), ("dub", "Dub"), ("dynamics365", "Dynamics 365"),
        ("eventbrite", "Eventbrite"), ("excel", "Excel"), ("exist", "Exist"),
        ("facebook", "Facebook"), ("fathom", "Fathom"), ("figma", "Figma"),
        ("freeagent", "Freeagent"), ("freshbooks", "FreshBooks"),
        ("github", "GitHub"), ("gitlab", "GitLab"), ("gmail", "Gmail"),
        ("googleads", "Google Ads"), ("google_analytics", "Google Analytics"),
        ("googlebigquery", "Google BigQuery"), ("googlecalendar", "Google Calendar"),
        ("google_classroom", "Google Classroom"), ("googledocs", "Google Docs"),
        ("googledrive", "Google Drive"), ("google_maps", "Google Maps"),
        ("googlemeet", "Google Meet"), ("googlephotos", "Google Photos"),
        ("google_search_console", "Google Search Console"),
        ("googlesheets", "Google Sheets"), ("googleslides", "Google Slides"),
        ("googlesuper", "Google Super"), ("googletasks", "Google Tasks"),
        ("gorgias", "Gorgias"), ("gumroad", "Gumroad"), ("harvest", "Harvest"),
        ("hubspot", "HubSpot"), ("hugging_face", "Hugging Face"),
        ("instagram", "Instagram"), ("intercom", "Intercom"), ("jira", "Jira"),
        ("kit", "Kit"), ("larksuite", "Lark / Feishu"), ("linear", "Linear"),
        ("linkedin", "LinkedIn"), ("linkhut", "Linkhut"), ("mailchimp", "Mailchimp"),
        ("microsoft_teams", "Microsoft Teams"), ("miro", "Miro"),
        ("monday", "Monday"), ("moneybird", "Moneybird"), ("mural", "Mural"),
        ("notion", "Notion"), ("omnisend", "Omnisend"), ("one_drive", "OneDrive"),
        ("outlook", "Outlook"), ("pagerduty", "PagerDuty"), ("prisma", "Prisma"),
        ("productboard", "Productboard"), ("pushbullet", "Pushbullet"),
        ("quickbooks", "QuickBooks"), ("reddit", "Reddit"), ("reddit_ads", "Reddit Ads"),
        ("roam", "Roam"), ("salesforce", "Salesforce"), ("sentry", "Sentry"),
        ("servicem8", "Servicem8"), ("share_point", "SharePoint"),
        ("shippo", "Shippo"), ("slack", "Slack"), ("slackbot", "Slackbot"),
        ("splitwise", "Splitwise"), ("square", "Square"),
        ("stack_exchange", "Stack Exchange"), ("strava", "Strava"),
        ("stripe", "Stripe"), ("supabase", "Supabase"),
        ("telegram", "Telegram"), ("ticketmaster", "Ticketmaster"), ("ticktick", "Ticktick"),
        ("timely", "Timely"), ("todoist", "Todoist"), ("toneden", "Toneden"),
        ("trello", "Trello"), ("twitter", "X"), ("typeform", "Typeform"), ("wakatime", "WakaTime"),
        ("webex", "Webex"), ("whatsapp", "WhatsApp Business"), ("wrike", "Wrike"),
        ("yandex", "Yandex"), ("ynab", "YNAB"), ("youtube", "YouTube"),
        ("zendesk", "Zendesk"), ("zoho", "Zoho"), ("zoho_bigin", "Zoho Bigin"),
        ("zoho_books", "Zoho Books"), ("zoho_desk", "Zoho Desk"),
        ("zoho_inventory", "Zoho Inventory"), ("zoho_invoice", "Zoho Invoice"),
        ("zoho_mail", "Zoho Mail"), ("zoom", "Zoom"),
    ]

    private static func category(slug: String, name: String) -> DetourIntegrationCategory {
        let key = "\(slug) \(name)".lowercased()
        if hasAny(["discord", "telegram", "slack", "teams", "webex", "whatsapp", "dialpad", "lark"], in: key) {
            return .chat
        }
        if hasAny(["facebook", "instagram", "linkedin", "reddit", "twitter", "youtube", "stack_exchange"], in: key) {
            return .social
        }
        if hasAny(productivityKeywords, in: key) {
            return .productivity
        }
        if hasAny(platformKeywords, in: key) {
            return .platform
        }
        return .tools
    }

    private static let productivityKeywords = [
        "gmail", "calendar", "drive", "docs", "sheets", "slides", "tasks", "todoist",
        "trello", "notion", "box", "dropbox", "sharepoint", "one_drive", "outlook",
        "miro", "mural", "monday", "clickup", "linear", "jira", "confluence",
        "asana", "basecamp", "wrike", "cal", "calendly", "typeform", "excel",
        "figma", "google",
    ]

    private static let platformKeywords = [
        "github", "gitlab", "bitbucket", "digital_ocean", "contentful", "supabase",
        "convex", "prisma", "sentry", "stripe", "salesforce", "hubspot", "quickbooks",
        "zendesk", "zoho",
    ]

    private static func hasAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
