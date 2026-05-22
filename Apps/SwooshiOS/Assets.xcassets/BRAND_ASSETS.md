# Brand asset sources

Each `*.imageset` in this catalog contains an SVG vector mark for a model
provider, chain, or chat-adapter target that swooshd integrates with.
The SVGs are bundled for nominative identification of those integrations
in the iOS UI — no claim of ownership is implied.

## Sources

| Imageset      | Used for          | Source                       | Reuse terms        |
|---------------|-------------------|------------------------------|--------------------|
| OpenAI        | openai            | User-supplied                | per OpenAI brand   |
| OpenRouter    | openrouter        | simpleicons.org              | CC0                |
| Google        | google            | simpleicons.org              | CC0                |
| Solana        | solana chain      | simpleicons.org              | CC0                |
| Ethereum      | ethereum chain    | simpleicons.org              | CC0                |
| BNBChain      | bnb chain         | simpleicons.org              | CC0                |
| Discord       | discord adapter   | simpleicons.org              | CC0                |
| Telegram      | telegram adapter  | simpleicons.org              | CC0                |
| GitHub        | github adapter    | simpleicons.org              | CC0                |
| Linear        | linear adapter    | simpleicons.org              | CC0                |
| WhatsApp      | whatsApp adapter  | simpleicons.org              | CC0                |
| Matrix        | beeperMatrix      | simpleicons.org              | CC0                |
| iMessage      | photonIMessage    | simpleicons.org              | CC0                |
| Resend        | resendEmail       | simpleicons.org              | CC0                |
| Webex         | webex adapter     | simpleicons.org              | CC0                |
| Mattermost    | mattermost        | simpleicons.org              | CC0                |
| GoogleChat    | googleChat        | simpleicons.org              | CC0                |
| X             | x adapter         | simpleicons.org              | CC0                |
| Slack         | slack adapter     | iconify.design (logos set)   | CC-BY-4.0          |
| Teams         | teams adapter     | iconify.design (logos set)   | CC-BY-4.0          |
| Messenger     | messenger adapter | iconify.design (logos set)   | CC-BY-4.0          |

CC0 marks are public-domain dedications by their creators on simpleicons.
CC-BY-4.0 marks (Slack / Teams / Messenger from iconify's `logos` set)
require attribution if redistributed independently of this app bundle.
The trademarks remain with each brand owner — bundling is for nominative
service identification only.

## Replacing with official brand-kit assets

If a brand publishes an updated official mark (e.g. via openai.com/brand
or slack.com/media-kit), drop the new `.svg` into the matching
`*.imageset/` folder and update its `Contents.json` filename. The
`ProviderLogo` / `ChannelLogo` / `ChainLogo` Swift code resolves images
by imageset name, so the lookup path is stable across asset updates.
