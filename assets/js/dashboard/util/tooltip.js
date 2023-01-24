import React, { useState } from "react";
import { usePopper } from 'react-popper';
import classNames from 'classnames'

export function Tooltip({ children, info, className, onClick, boundary }) {
  const [visible, setVisible] = useState(false);
  const [referenceElement, setReferenceElement] = useState(null);
  const [popperElement, setPopperElement] = useState(null);
  const [arrowElement, setArrowElement] = useState(null);
  const { styles, attributes } = usePopper(referenceElement, popperElement, {
    placement: 'top',
    modifiers: [
      { name: 'arrow', options: { element: arrowElement } },
      {
        name: 'offset',
        options: {
          offset: [0, 4],
        },
      },
      boundary && {
        name: 'preventOverflow',
        options: {
          boundary: boundary,
        },
      },
    ],
  });

  return (
    <div className={classNames('relative', className)}>
      <div ref={setReferenceElement} onMouseEnter={() => setVisible(true)} onMouseLeave={() => setVisible(false)} onClick={onClick}>
        {children}

      </div>
      {info && visible && <div ref={setPopperElement} style={styles.popper} {...attributes.popper} className="z-50 p-2 rounded text-sm text-gray-100 font-bold popper-tooltip" role="tooltip">
        {info}
        <div ref={setArrowElement} style={styles.arrow} className="tooltip-arrow"></div>
      </div>
      }
    </div>
  )
}
