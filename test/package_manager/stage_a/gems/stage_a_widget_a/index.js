import React from 'react'
import ms from 'ms'

import './index.css'

export { React, ms }

export default () => React.createElement('span', { className: 'stageAWidgeta' }, ms(60000))
