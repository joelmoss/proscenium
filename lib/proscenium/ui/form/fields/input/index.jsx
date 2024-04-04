import clsx from 'clsx'
import PropTypes from 'prop-types'

import dsx from '/hue/lib/hue/utils/dsx'
import { useFormError } from '../../hooks'

import styles from './index.module.css'

const Input = ({
  label,
  hint,
  className,
  inputClassName,
  errorAttrName,
  inputRef,
  children,
  ...props
}) => {
  const [error, hasError] = useFormError(errorAttrName || props.name)

  return (
    <div className={clsx(styles.fieldWrapper, className)} {...dsx({ fieldError: hasError })}>
      <label>
        <span>
          {label ? <span>{label}</span> : null}
          {hasError ? <span>{error}</span> : null}
        </span>

        {children || <input className={inputClassName || styles.input} {...props} ref={inputRef} />}
      </label>

      {hint ? <div className={styles.hint}>{hint}</div> : null}
    </div>
  )
}
Input.displayName = 'Hue.Form.Fields.Input'
Input.propTypes = {
  name: PropTypes.string.isRequired,

  label: PropTypes.oneOfType([PropTypes.string, PropTypes.number, PropTypes.element]),

  // Input `type` attribute. Default: 'text'.
  type: PropTypes.string,

  // Custom class name. This will be appended to the default class.
  className: PropTypes.string,

  // Custom class name for the actual input element. This will replace the default class.
  inputClassName: PropTypes.string,

  // The name of the attribute to use for the error message. Default: 'props.name'.
  errorAttrName: PropTypes.string,

  children: PropTypes.node,

  inputRef: PropTypes.oneOfType([
    PropTypes.func,
    PropTypes.shape({ current: PropTypes.instanceOf(Element) })
  ]),

  id: PropTypes.string,
  hint: PropTypes.string,
  disabled: PropTypes.bool

  // All remaining non-descript props will be forwarded to the <input> element.
}
Input.defaultProps = {
  type: 'text'
}

export default Input
