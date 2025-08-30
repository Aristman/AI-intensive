import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import AgentWebsite from '../AgentWebsite/AgentWebsite.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <AgentWebsite />
  </StrictMode>,
)
