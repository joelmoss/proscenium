import clsx from 'clsx'
import PropTypes from 'prop-types'

import dsx from '/hue/lib/hue/utils/dsx'
import { useFormError } from '../../hooks'

import styles from './index.module.css'

const Component = ({ label, hint, className, errorAttrName, ...props }) => {
  const [error, hasError] = useFormError(errorAttrName || props.name)

  return (
    <div className={clsx(styles.fieldWrapper, className)} {...dsx({ fieldError: hasError })}>
      <label>
        <input type="radio" {...props} />

        <span>{label}</span>
      </label>

      {hasError ? <div className={styles.error}>{error}</div> : null}
      {hint ? <div className={styles.hint}>{hint}</div> : null}
    </div>
  )
}

Component.displayName = 'Hue.Form.Fields.RadioInput'
Component.propTypes = {
  name: PropTypes.string.isRequired,
  label: PropTypes.oneOfType([PropTypes.string, PropTypes.number, PropTypes.element]).isRequired,

  // Custom class name. This will be appended to the default class.
  className: PropTypes.string,

  // The name of the attribute to use for the error message. Default: 'props.name'.
  errorAttrName: PropTypes.string,

  id: PropTypes.string,
  hint: PropTypes.string,
  disabled: PropTypes.bool

  // All remaining non-descript props will be forwarded to the <input> element.
}

export default Component
