import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';

import styles from './index.module.css';

const features = [
  {
    title: 'Private by default',
    description:
      'All durable state — memories, sessions, audit records — lives in a local, hash-chained ActantDB ledger. Nothing leaves your Mac unless you configure a provider.',
  },
  {
    title: 'Typed & permissioned',
    description:
      'Every tool is typed. Every risky action is permissioned. SwooshFirewall enforces the permission model — tools cannot bypass it.',
  },
  {
    title: 'Auditable & replayable',
    description:
      'Every agent step is logged. Every workflow is replayable. Every memory is inspectable. The full audit trail is yours, always.',
  },
  {
    title: 'Local when possible',
    description:
      'SwooshMLX runs 7B–13B models on Apple silicon. SwooshFoundation uses Apple Intelligence on-device. Remote providers are opt-in.',
  },
  {
    title: 'Scout personalization',
    description:
      'Scout scans your dev environment and proposes memory candidates. You review and approve before anything reaches the agent prompt.',
  },
  {
    title: 'Mac + iPhone',
    description:
      'swooshd runs the kernel on your Mac. The iPhone is a thin bearer-gated HTTP client today, with a fully embedded local kernel on the roadmap.',
  },
];

function Feature({title, description}: {title: string; description: string}) {
  return (
    <div className={clsx('col col--4', styles.featureCard)}>
      <Heading as="h3">{title}</Heading>
      <p>{description}</p>
    </div>
  );
}

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          {siteConfig.title}
        </Heading>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <div className={styles.buttons}>
          <Link className="button button--secondary button--lg" to="/docs/getting-started">
            Get started →
          </Link>
          <Link
            className="button button--outline button--secondary button--lg"
            to="/docs/architecture"
            style={{marginLeft: '1rem'}}>
            Architecture
          </Link>
        </div>
      </div>
    </header>
  );
}

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.title}
      description="Swift-native, MLX-capable, Apple-first autonomous agent runtime. Private by default. Typed by design. Local when possible. Auditable always.">
      <HomepageHeader />
      <main>
        <section className={styles.features}>
          <div className="container">
            <div className="row">
              {features.map((f, i) => (
                <Feature key={i} {...f} />
              ))}
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}
