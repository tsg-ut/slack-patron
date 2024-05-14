import React, { Component } from 'react';
import MrkdwnText from './MrkdwnText';

import './Element.less';

export class Text extends Component {
  render() {
    const {text} = this.props;
    if (text.type === 'mrkdwn') {
      return <MrkdwnText text={text.text} />;
    }
    if (text.type === 'plain_text') {
      return <span className="plain-text">{text.text}</span>;
    }
    return (
      <span style={{color: 'red'}}>
        ERROR: Unsupported text type: {text.type}
      </span>
    );
  }
}

// https://api.slack.com/reference/block-kit/block-elements#image
export class Image extends Component {
  render() {
    const {image} = this.props;
    return (
      <img
        className="image-element"
        src={image.image_url}
        alt={image.alt_text}
      />
    );
  }
}

// https://api.slack.com/reference/block-kit/block-elements#button
export class Button extends Component {
  render() {
    const {button} = this.props;
    return (
      <button
        className={`button-element button-element-${button.style || 'default'}`}
        disabled
      >
        <Text text={button.text} />
      </button>
    );
  }
}

export default class extends Component {
  constructor(props) {
    super(props);
    this.state = {
      isHidden: true,
    };
    this.handleToggleRawData = this.handleToggleRawData.bind(this);
  }

  handleToggleRawData() {
    this.setState((state) => ({
      isHidden: !state.isHidden,
    }));
  }

  render() {
    const {element} = this.props;

    if (element.type === 'button') {
      return (
        <span className="slack-message-element">
          <Button button={element} />
        </span>
      );
    }

    if (element.type === 'image') {
      return (
        <span className="slack-message-element">
          <Image image={element} />
        </span>
      );
    }

    return (
      <span className="slack-message-element">
        <div className="slack-message-unsupported-element" onClick={this.handleToggleRawData}>
          ⚠️ Unsupported element (click to show raw data)
        </div>
        { !this.state.isHidden && (
          <pre className="slack-message-element-raw">
            {JSON.stringify(element, null, '  ')}
          </pre>
        ) }
      </span>
    );
  }
}