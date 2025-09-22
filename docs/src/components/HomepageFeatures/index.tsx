import type {ReactNode} from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  emoji: string;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'Typed Database Records',
    emoji: '🎯',
    description: (
      <>
        Work with typed record classes instead of raw maps. Generated classes provide 
        property-style access, automatic type conversion, and intelligent CRUD operations.
      </>
    ),
  },
  {
    title: 'Smart Exception Handling',
    emoji: '🛡️',
    description: (
      <>
        REST API-like exception hierarchy with business-focused error categories. 
        Handle database errors gracefully with meaningful exception types and context.
      </>
    ),
  },
  {
    title: 'Flutter Integration',
    emoji: '🚀',
    description: (
      <>
        Seamless integration with Flutter through reactive widgets, typed record support, 
        and real-time UI updates. Build data-driven Flutter apps with minimal boilerplate.
      </>
    ),
  },
];

function Feature({title, emoji, description}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <div className={styles.featureEmoji}>{emoji}</div>
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
