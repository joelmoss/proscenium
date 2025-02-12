import { useCallback, useState } from 'react'
import PropTypes from 'prop-types'
import exact from 'prop-types-exact'

import SmartSelect, {
  propTypes as smartSelectPropTypes
} from '/hue/app/components/lib/smart_select'

const Component = ({ inputName, ...props }) => {
  const [selected, setSelected] = useState(() => {
    return Array.isArray(props.initialSelectedItem)
      ? props.initialSelectedItem
      : [props.initialSelectedItem]
  })

  const onChange = useCallback(values => {
    if (Array.isArray(values)) {
      setSelected(values)
    } else {
      setSelected([values?.value])
    }
  }, [])

  return (
    <>
      <SmartSelect {...props} onChange={onChange} />

      {selected.length === 0 && <input type="hidden" name={inputName} value="" />}
      {selected.map((item, i) => (
        <input
          key={item?.value || i}
          type="hidden"
          name={inputName}
          value={item?.value || item || ''}
        />
      ))}
    </>
  )
}

Component.displayName = 'Hue.Form.Fields.Select'
Component.propTypes = exact({
  inputName: PropTypes.string.isRequired,
  ...smartSelectPropTypes
})

export default Component
