import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    {
      type: 'doc',
      id: 'intro',
      label: 'Introduction',
    },
    {
      type: 'category',
      label: 'Getting Started',
      collapsed: false,
      items: [
        'getting-started',
        'cli',
      ],
    },
    {
      type: 'category',
      label: 'Architecture',
      items: [
        'architecture',
        'modules',
        'scout',
      ],
    },
    {
      type: 'category',
      label: 'Security & Permissions',
      items: [
        'permissions',
      ],
    },
    {
      type: 'category',
      label: 'iOS & Generative UI',
      items: [
        'ios',
        'generative-ui',
      ],
    },
  ],
};

export default sidebars;
