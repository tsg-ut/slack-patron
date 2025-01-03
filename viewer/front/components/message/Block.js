import React, { Component } from 'react';
import Emoji from './Emoji';
import Element, { Image, Text } from './Element';
import UserMention from './UserMention';
import ChannelMention from './ChannelMention';

import './Block.less';

class RichTextSection extends Component {
  getClasses(style) {
    const {bold, italic, code, strike} = style || {};
    return [
      ...(bold ? ['bold'] : []),
      ...(italic ? ['italic'] : []),
      ...(strike ? ['strike'] : []),
      ...(code ? ['code'] : []),
    ].join(' ');
  }
  render() {
    const {elements} = this.props;
    return (
      <div className="rich-text-section">
        {
          elements.map((element, index) => {
            if (element.type === 'text') {
              return <span key={index} className={this.getClasses(element.style)}>{element.text}</span>
            }
            if (element.type === 'link') {
              return (
                <a
                  key={index}
                  href={element.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={this.getClasses(element.style)}
                >
                  {element.text || element.url}
                </a>
              );
            }
            if (element.type === 'emoji') {
              return <Emoji key={index} name={element.name} className={this.getClasses(element.style)} />
            }
            if (element.type === 'user') {
              return <UserMention key={index} id={element.user_id} className={this.getClasses(element.style)} />
            }
            if (element.type === 'channel') {
              return <ChannelMention key={index} id={element.channel_id} className={this.getClasses(element.style)} />
            }
            if (element.type === 'broadcast') {
              return <span key={index} className={this.getClasses(element.style)}>@{element.range}</span>
            }
            // TODO: team, usergroup, date
            return <code key={index}>{JSON.stringify(element, null, '  ')}</code>
          })
        }
      </div>
    );
  }
}

class RichTextList extends Component {
  renderItems() {
    return this.props.elements.map((element, index) => {
      if (element.type === 'rich_text_section') {
        return <li key={index}><RichTextSection elements={element.elements} /></li>
      }
      return <span style={{color: 'red'}}>ERROR: Unsupported element type {element.type}</span>
    });
  }
  render() {
    const {style} = this.props;
    if (style === 'ordered') {
      return (
        <ol className="rich-text-list">
          {this.renderItems()}
        </ol>
      );
    }
    if (style === 'bullet') {
      return (
        <ul className="rich-text-list">
          {this.renderItems()}
        </ul>
      );
    }
    return <span style={{color: 'red'}}>ERROR: Unsupported list style {style}</span>
  }
}

class RichTextPreformatted extends Component {
  render() {
    const {elements} = this.props;
    return (
      <div className="rich-text-preformatted">
        {
          elements.map((element, index) => {
            if (element.type === 'text') {
              return <span key={index}>{element.text}</span>
            }
            if (element.type === 'link') {
              return (
                <a
                  key={index}
                  href={element.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {element.text || element.url}
                </a>
              );
            }
            return <code key={index} style={{color: 'red'}}>{JSON.stringify(element)}</code>
          })
        }
      </div>
    );
  }
}

class RichTextQuote extends Component {
  render() {
    return (
      <div className="rich-text-quote">
        <RichTextSection elements={this.props.elements} />
      </div>
    );
  }
}

class RichTextBlock extends Component {
  render() {
    const {elements} = this.props;
    return (
      <div className="rich-text-block">
        {
          elements.map((element, index) => {
            if (element.type === 'rich_text_section') {
              return <RichTextSection key={index} elements={element.elements} />
            }
            if (element.type === 'rich_text_list') {
              return <RichTextList key={index} elements={element.elements} style={element.style} />
            }
            if (element.type === 'rich_text_preformatted') {
              return <RichTextPreformatted key={index} elements={element.elements} />
            }
            if (element.type === 'rich_text_quote') {
              return <RichTextQuote key={index} elements={element.elements} />
            }
            return <span style={{color: 'red'}}>ERROR: Unsupported element type {element.type}</span>
          })
        }
      </div>
    );
  }
}

class SectionBlock extends Component {
  render() {
    const {text, fields, accessory} = this.props;

    return (
      <div className="section-block">
        <div className="section-block-body">
          {text && (<div className="section-block-text">
            <Text text={text} />
          </div>)}
          {fields && fields.length > 0 && (
            <div className="section-block-fields">
              {fields.map((field, index) => (
                <div key={index} className="section-block-field">
                  <Text text={field} />
                </div>
              ))}
            </div>
          )}
        </div>
        {accessory && (
          <div className="section-block-accessory">
            <Element element={accessory} />
          </div>
        )}
      </div>
    );
  }
}

// https://api.slack.com/reference/block-kit/blocks#context
class ContextBlock extends Component {
  render() {
    const {elements} = this.props;

    return (
      <div className="context-block">
        {elements.map((element, index) => {
          if (element.type === 'image') {
            return (
              <div key={index} className="context-block-image">
                <Image image={element} />
              </div>
            );
          }
          return (
            <div key={index} className="context-block-element">
              <Text text={element} />
            </div>
          );
        })}
      </div>
    );
  }
}

// https://api.slack.com/reference/block-kit/blocks#divider
class DividerBlock extends Component {
  render() {
    return (
      <div className="divider-block">
        <hr />
      </div>
    );
  }
}

// https://api.slack.com/reference/block-kit/blocks#actions
class ActionsBlock extends Component {
  render() {
    const {elements} = this.props;

    return (
      <div className="actions-block">
        {elements.map((element, index) => (
          <div key={index} className="actions-block-element">
            <Element element={element} />
          </div>
        ))}
      </div>
    );
  }
}

// https://api.slack.com/reference/block-kit/blocks#header
class HeaderBlock extends Component {
  render() {
    return (
      <div className="header-block">
        <Text text={this.props.text} />
      </div>
    );
  }
}

// https://api.slack.com/reference/block-kit/blocks#image
class ImageBlock extends Component {
  render() {
    return (
      <div className="image-block">
        <div className="image-block-title">
          {this.props.image.title && (<Text text={this.props.image.title} />)}
        </div>
        <Image image={this.props.image} />
      </div>
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
    const {block} = this.props;

    if (block.type === 'rich_text') {
      return (
        <div className="slack-message-block">
          <RichTextBlock elements={block.elements} />
        </div>
      )
    }

    if (block.type === 'section') {
      return (
        <div className="slack-message-block">
          <SectionBlock text={block.text} fields={block.fields} accessory={block.accessory} />
        </div>
      )
    }

    if (block.type === 'context') {
      return (
        <div className="slack-message-block">
          <ContextBlock elements={block.elements} />
        </div>
      )
    }

    if (block.type === 'divider') {
      return (
        <div className="slack-message-block">
          <DividerBlock />
        </div>
      )
    }

    if (block.type === 'actions') {
      return (
        <div className="slack-message-block">
          <ActionsBlock elements={block.elements} />
        </div>
      )
    }

    if (block.type === 'header') {
      return (
        <div className="slack-message-block">
          <HeaderBlock text={block.text} />
        </div>
      )
    }

    if (block.type === 'image') {
      return (
        <div className="slack-message-block">
          <ImageBlock image={block} />
        </div>
      )
    }

    return (
      <div className="slack-message-block">
        <div className="slack-message-unsupported-block" onClick={this.handleToggleRawData}>
          ⚠️ Unsupported block (click to show raw data)
        </div>
        { !this.state.isHidden && (
          <pre className="slack-message-block-raw">
            {JSON.stringify(block, null, '  ')}
          </pre>
        ) }
      </div>
    );
  }
}
