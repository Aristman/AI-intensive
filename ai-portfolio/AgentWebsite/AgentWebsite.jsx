import React, { useState } from 'react';

export default function AgentWebsite() {
  const [activeSection, setActiveSection] = useState('about');

  const handleNavigation = (section) => {
    setActiveSection(section);
  };

  return (
    <div className="font-sans antialiased bg-gray-100 text-gray-900 min-h-screen flex flex-col">
      <header className="bg-white shadow-md py-4">
        <div className="container mx-auto px-4">
          <nav className="flex items-center justify-between">
            <div>
              <a href="#" className="font-bold text-xl text-gray-800">
                Agent AI
              </a>
            </div>
            <div>
              <ul className="flex space-x-6">
                <li>
                  <button onClick={() => handleNavigation('about')} className={`hover:text-blue-500 ${activeSection === 'about' ? 'font-semibold text-blue-500' : ''}`}>
                    About
                  </button>
                </li>
                <li>
                  <button onClick={() => handleNavigation('portfolio')} className={`hover:text-blue-500 ${activeSection === 'portfolio' ? 'font-semibold text-blue-500' : ''}`}>
                    Portfolio
                  </button>
                </li>
                <li>
                  <button onClick={() => handleNavigation('reviews')} className={`hover:text-blue-500 ${activeSection === 'reviews' ? 'font-semibold text-blue-500' : ''}`}>
                    Reviews
                  </button>
                </li>
                <li>
                  <button onClick={() => handleNavigation('contacts')} className={`hover:text-blue-500 ${activeSection === 'contacts' ? 'font-semibold text-blue-500' : ''}`}>
                    Contacts
                  </button>
                </li>
              </ul>
            </div>
          </nav>
        </div>
      </header>

      <main className="container mx-auto px-4 py-8 flex-grow">
        {activeSection === 'about' && <AboutSection />}
        {activeSection === 'portfolio' && <PortfolioSection />}
        {activeSection === 'reviews' && <ReviewsSection />}
        {activeSection === 'contacts' && <ContactSection />}
      </main>

      <footer className="bg-gray-800 text-white py-4 mt-8">
        <div className="container mx-auto px-4 text-center">
          <p>&copy; 2024 Agent AI. All rights reserved.</p>
        </div>
      </footer>
    </div>
  );
}

function AboutSection() {
  return (
    <section>
      <h2 className="text-3xl font-bold mb-4">About Me</h2>
      <div className="flex flex-col md:flex-row gap-8">
        <div className="md:w-1/3">
           <div className="bg-gray-200 border-2 border-dashed rounded-xl w-full h-64 md:h-auto" />
        </div>
        <div className="md:w-2/3">
          <p className="mb-4">
            I am a dedicated AI agent developer with a passion for creating intelligent and efficient systems. My goal is to leverage the power of AI to solve complex problems and improve various aspects of our lives.
          </p>
          <p className="mb-4">
            With expertise in machine learning, natural language processing, and robotics, I am committed to delivering innovative and reliable AI solutions.
          </p>
          <p>
            Let's build the future together!
          </p>
        </div>
      </div>

    </section>
  );
}

function PortfolioSection() {
  return (
    <section>
      <h2 className="text-3xl font-bold mb-4">Portfolio</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <div className="bg-white rounded-lg shadow-md p-4">
           <div className="bg-gray-200 border-2 border-dashed rounded-xl w-full h-48 mb-4" />
          <h3 className="font-semibold text-lg">AI Assistant for Customer Service</h3>
          <p className="text-gray-700">Developed an AI assistant to handle customer inquiries and provide instant support.</p>
        </div>
        <div className="bg-white rounded-lg shadow-md p-4">
           <div className="bg-gray-200 border-2 border-dashed rounded-xl w-full h-48 mb-4" />
          <h3 className="font-semibold text-lg">Robotic Process Automation</h3>
          <p className="text-gray-700">Automated repetitive tasks using robotic process automation to improve efficiency.</p>
        </div>
        <div className="bg-white rounded-lg shadow-md p-4">
           <div className="bg-gray-200 border-2 border-dashed rounded-xl w-full h-48 mb-4" />
          <h3 className="font-semibold text-lg">AI-Powered Recommendation System</h3>
          <p className="text-gray-700">Built an AI-powered recommendation system to personalize user experiences.</p>
        </div>
      </div>
    </section>
  );
}

function ReviewsSection() {
  return (
    <section>
      <h2 className="text-3xl font-bold mb-4">Reviews</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-white rounded-lg shadow-md p-4">
          <p className="text-gray-700 italic mb-2">"The AI agent developed by this developer exceeded all expectations. It has significantly improved our operational efficiency."</p>
          <p className="font-semibold">- John Doe, CEO</p>
        </div>
        <div className="bg-white rounded-lg shadow-md p-4">
          <p className="text-gray-700 italic mb-2">"I am extremely satisfied with the AI solutions provided. The developer is highly skilled and professional."</p>
          <p className="font-semibold">- Jane Smith, CTO</p>
        </div>
      </div>
    </section>
  );
}

function ContactSection() {
  return (
    <section>
      <h2 className="text-3xl font-bold mb-4">Contact Me</h2>
      <div className="bg-white rounded-lg shadow-md p-6">
        <form>
          <div className="mb-4">
            <label htmlFor="name" className="block text-gray-700 text-sm font-bold mb-2">
              Name:
            </label>
            <input
              type="text"
              id="name"
              className="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
              placeholder="Your Name"
            />
          </div>
          <div className="mb-4">
            <label htmlFor="email" className="block text-gray-700 text-sm font-bold mb-2">
              Email:
            </label>
            <input
              type="email"
              id="email"
              className="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
              placeholder="Your Email"
            />
          </div>
          <div className="mb-6">
            <label htmlFor="message" className="block text-gray-700 text-sm font-bold mb-2">
              Message:
            </label>
            <textarea
              id="message"
              className="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
              placeholder="Your Message"
            ></textarea>
          </div>
          <div className="flex items-center justify-between">
            <button
              className="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline"
              type="button"
            >
              Send Message
            </button>
          </div>
        </form>
      </div>
    </section>
  );
}