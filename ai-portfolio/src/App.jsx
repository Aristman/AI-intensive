import React, { useState } from 'react';
import { Github, Linkedin, Mail, Phone, MapPin, Star, Menu, X } from 'lucide-react';
import { motion } from 'framer-motion';

export default function App() {
  const [isMenuOpen, setIsMenuOpen] = useState(false);

  const toggleMenu = () => {
    setIsMenuOpen(!isMenuOpen);
  };

  const portfolioItems = [
    {
      id: 1,
      title: "AI Chatbot Development",
      description: "Custom conversational AI for customer support automation",
      image: "https://placehold.co/600x400/6366f1/ffffff?text=AI+Chatbot"
    },
    {
      id: 2,
      title: "Predictive Analytics System",
      description: "Machine learning models for business forecasting",
      image: "https://placehold.co/600x400/8b5cf6/ffffff?text=Analytics"
    },
    {
      id: 3,
      title: "Automated Trading Agent",
      description: "Intelligent algorithmic trading system",
      image: "https://placehold.co/600x400/06b6d4/ffffff?text=Trading+AI"
    },
    {
      id: 4,
      title: "Smart Recommendation Engine",
      description: "Personalized content recommendation system",
      image: "https://placehold.co/600x400/10b981/ffffff?text=Recommendations"
    }
  ];

  const testimonials = [
    {
      id: 1,
      name: "Sarah Johnson",
      role: "CTO, TechStart Inc.",
      content: "Exceptional work on our AI implementation. Delivered beyond expectations.",
      avatar: "https://placehold.co/80x80/f3f4f6/6366f1?text=SJ"
    },
    {
      id: 2,
      name: "Michael Chen",
      role: "Product Director, InnovateLab",
      content: "Professional, knowledgeable, and delivered on time. Highly recommended.",
      avatar: "https://placehold.co/80x80/f3f4f6/8b5cf6?text=MC"
    },
    {
      id: 3,
      name: "Emily Rodriguez",
      role: "CEO, DataDriven Solutions",
      content: "Transformed our business processes with intelligent automation.",
      avatar: "https://placehold.co/80x80/f3f4f6/06b6d4?text=ER"
    }
  ];

  const containerVariants = {
    hidden: { opacity: 0 },
    visible: {
      opacity: 1,
      transition: {
        staggerChildren: 0.1
      }
    }
  };

  const itemVariants = {
    hidden: { y: 20, opacity: 0 },
    visible: {
      y: 0,
      opacity: 1,
      transition: {
        duration: 0.5
      }
    }
  };

  return (
    <div className="min-h-screen bg-white text-gray-900">
      {/* Navigation */}
      <nav className="fixed w-full bg-white/90 backdrop-blur-sm z-50 border-b border-gray-100">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-16">
            <motion.div 
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              className="text-xl font-semibold"
            >
              AI Developer
            </motion.div>
            
            {/* Desktop Navigation */}
            <div className="hidden md:flex space-x-8">
              <a href="#about" className="text-gray-600 hover:text-gray-900 transition-colors">About</a>
              <a href="#portfolio" className="text-gray-600 hover:text-gray-900 transition-colors">Portfolio</a>
              <a href="#testimonials" className="text-gray-600 hover:text-gray-900 transition-colors">Reviews</a>
              <a href="#contact" className="text-gray-600 hover:text-gray-900 transition-colors">Contact</a>
            </div>

            {/* Mobile menu button */}
            <div className="md:hidden">
              <button
                onClick={toggleMenu}
                className="text-gray-600 hover:text-gray-900 focus:outline-none"
              >
                {isMenuOpen ? <X size={24} /> : <Menu size={24} />}
              </button>
            </div>
          </div>
        </div>

        {/* Mobile Navigation */}
        {isMenuOpen && (
          <motion.div 
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            className="md:hidden bg-white border-t border-gray-100"
          >
            <div className="px-2 pt-2 pb-3 space-y-1">
              <a href="#about" className="block px-3 py-2 text-gray-600 hover:text-gray-900">About</a>
              <a href="#portfolio" className="block px-3 py-2 text-gray-600 hover:text-gray-900">Portfolio</a>
              <a href="#testimonials" className="block px-3 py-2 text-gray-600 hover:text-gray-900">Reviews</a>
              <a href="#contact" className="block px-3 py-2 text-gray-600 hover:text-gray-900">Contact</a>
            </div>
          </motion.div>
        )}
      </nav>

      {/* Hero Section */}
      <section className="pt-24 pb-16 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <motion.div 
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8 }}
            className="text-center max-w-4xl mx-auto"
          >
            <h1 className="text-4xl md:text-6xl font-bold mb-6">
              Building Intelligent <span className="text-indigo-600">AI Systems</span>
            </h1>
            <p className="text-xl text-gray-600 mb-8 max-w-2xl mx-auto">
              Specialized in developing cutting-edge AI agents and systems that transform businesses and solve complex challenges.
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <a 
                href="#contact" 
                className="bg-indigo-600 text-white px-8 py-3 rounded-lg hover:bg-indigo-700 transition-colors"
              >
                Get Started
              </a>
              <a 
                href="#portfolio" 
                className="border border-gray-300 text-gray-700 px-8 py-3 rounded-lg hover:bg-gray-50 transition-colors"
              >
                View Work
              </a>
            </div>
          </motion.div>
        </div>
      </section>

      {/* About Section */}
      <section id="about" className="py-16 px-4 sm:px-6 lg:px-8 bg-gray-50">
        <div className="max-w-7xl mx-auto">
          <motion.div
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true }}
            variants={containerVariants}
            className="grid md:grid-cols-2 gap-12 items-center"
          >
            <motion.div variants={itemVariants}>
              <h2 className="text-3xl font-bold mb-6">About Me</h2>
              <p className="text-gray-600 mb-6">
                I'm a passionate AI developer with expertise in creating intelligent systems and agents that drive innovation. 
                With a strong foundation in machine learning, natural language processing, and automated decision-making, 
                I help businesses harness the power of artificial intelligence.
              </p>
              <p className="text-gray-600 mb-6">
                My approach combines technical excellence with strategic thinking to deliver solutions that not only work 
                but also provide real business value. I specialize in building scalable AI systems that adapt and grow 
                with your organization's needs.
              </p>
              <div className="grid grid-cols-2 gap-4">
                <div className="bg-white p-4 rounded-lg shadow-sm">
                  <h3 className="font-semibold text-lg mb-2">Expertise</h3>
                  <ul className="text-gray-600 space-y-1">
                    <li>• Machine Learning</li>
                    <li>• NLP & Conversational AI</li>
                    <li>• Automated Agents</li>
                    <li>• Predictive Analytics</li>
                  </ul>
                </div>
                <div className="bg-white p-4 rounded-lg shadow-sm">
                  <h3 className="font-semibold text-lg mb-2">Focus Areas</h3>
                  <ul className="text-gray-600 space-y-1">
                    <li>• Business Automation</li>
                    <li>• Data Intelligence</li>
                    <li>• Process Optimization</li>
                    <li>• Scalable Solutions</li>
                  </ul>
                </div>
              </div>
            </motion.div>
            <motion.div variants={itemVariants} className="flex justify-center">
              <div className="relative">
                <div className="w-80 h-80 bg-gradient-to-br from-indigo-500 to-purple-600 rounded-full"></div>
                <div className="absolute -bottom-4 -right-4 bg-white p-6 rounded-lg shadow-lg">
                  <div className="text-2xl font-bold text-indigo-600">3+</div>
                  <div className="text-gray-600">Years Experience</div>
                </div>
              </div>
            </motion.div>
          </motion.div>
        </div>
      </section>

      {/* Portfolio Section */}
      <section id="portfolio" className="py-16 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <motion.div
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true }}
            variants={containerVariants}
            className="text-center mb-12"
          >
            <motion.h2 variants={itemVariants} className="text-3xl font-bold mb-4">Portfolio</motion.h2>
            <motion.p variants={itemVariants} className="text-gray-600 max-w-2xl mx-auto">
              Explore my recent projects showcasing innovative AI solutions and intelligent systems.
            </motion.p>
          </motion.div>

          <motion.div 
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true }}
            variants={containerVariants}
            className="grid md:grid-cols-2 lg:grid-cols-2 gap-8"
          >
            {portfolioItems.map((item, index) => (
              <motion.div 
                key={item.id}
                variants={itemVariants}
                className="bg-white rounded-xl overflow-hidden shadow-lg hover:shadow-xl transition-shadow"
              >
                <img 
                  src={item.image} 
                  alt={item.title}
                  className="w-full h-48 object-cover"
                />
                <div className="p-6">
                  <h3 className="text-xl font-semibold mb-2">{item.title}</h3>
                  <p className="text-gray-600">{item.description}</p>
                </div>
              </motion.div>
            ))}
          </motion.div>
        </div>
      </section>

      {/* Testimonials Section */}
      <section id="testimonials" className="py-16 px-4 sm:px-6 lg:px-8 bg-gray-50">
        <div className="max-w-7xl mx-auto">
          <motion.div
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true }}
            variants={containerVariants}
            className="text-center mb-12"
          >
            <motion.h2 variants={itemVariants} className="text-3xl font-bold mb-4">Client Reviews</motion.h2>
            <motion.p variants={itemVariants} className="text-gray-600 max-w-2xl mx-auto">
              What clients say about working with me on their AI projects.
            </motion.p>
          </motion.div>

          <motion.div 
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true }}
            variants={containerVariants}
            className="grid md:grid-cols-3 gap-8"
          >
            {testimonials.map((testimonial, index) => (
              <motion.div 
                key={testimonial.id}
                variants={itemVariants}
                className="bg-white p-6 rounded-xl shadow-lg"
              >
                <div className="flex mb-4">
                  {[...Array(5)].map((_, i) => (
                    <Star key={i} size={20} className="text-yellow-400 fill-current" />
                  ))}
                </div>
                <p className="text-gray-600 mb-6 italic">"{testimonial.content}"</p>
                <div className="flex items-center">
                  <img 
                    src={testimonial.avatar} 
                    alt={testimonial.name}
                    className="w-12 h-12 rounded-full mr-4"
                  />
                  <div>
                    <div className="font-semibold">{testimonial.name}</div>
                    <div className="text-gray-500 text-sm">{testimonial.role}</div>
                  </div>
                </div>
              </motion.div>
            ))}
          </motion.div>
        </div>
      </section>

      {/* Contact Section */}
      <section id="contact" className="py-16 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <motion.div
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true }}
            variants={containerVariants}
            className="text-center mb-12"
          >
            <motion.h2 variants={itemVariants} className="text-3xl font-bold mb-4">Get In Touch</motion.h2>
            <motion.p variants={itemVariants} className="text-gray-600 max-w-2xl mx-auto">
              Ready to transform your business with AI? Let's discuss your project.
            </motion.p>
          </motion.div>

          <motion.div 
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true }}
            variants={containerVariants}
            className="grid md:grid-cols-2 gap-12"
          >
            <motion.div variants={itemVariants}>
              <h3 className="text-xl font-semibold mb-6">Contact Information</h3>
              <div className="space-y-4">
                <div className="flex items-center">
                  <Mail className="text-indigo-600 mr-3" size={20} />
                  <span>contact@aidveloper.com</span>
                </div>
                <div className="flex items-center">
                  <Phone className="text-indigo-600 mr-3" size={20} />
                  <span>+1 (555) 123-4567</span>
                </div>
                <div className="flex items-center">
                  <MapPin className="text-indigo-600 mr-3" size={20} />
                  <span>San Francisco, CA</span>
                </div>
              </div>
              
              <div className="mt-8">
                <h4 className="font-semibold mb-4">Follow Me</h4>
                <div className="flex space-x-4">
                  <a href="#" className="bg-gray-100 p-3 rounded-full hover:bg-indigo-100 transition-colors">
                    <Github className="text-gray-600" size={20} />
                  </a>
                  <a href="#" className="bg-gray-100 p-3 rounded-full hover:bg-indigo-100 transition-colors">
                    <Linkedin className="text-gray-600" size={20} />
                  </a>
                </div>
              </div>
            </motion.div>

            <motion.div variants={itemVariants}>
              <form className="space-y-6">
                <div>
                  <label htmlFor="name" className="block text-sm font-medium text-gray-700 mb-1">Name</label>
                  <input 
                    type="text" 
                    id="name" 
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
                    placeholder="Your name"
                  />
                </div>
                <div>
                  <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">Email</label>
                  <input 
                    type="email" 
                    id="email" 
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
                    placeholder="your@email.com"
                  />
                </div>
                <div>
                  <label htmlFor="message" className="block text-sm font-medium text-gray-700 mb-1">Message</label>
                  <textarea 
                    id="message" 
                    rows={4}
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
                    placeholder="Tell me about your project..."
                  ></textarea>
                </div>
                <button 
                  type="submit"
                  className="w-full bg-indigo-600 text-white py-3 rounded-lg hover:bg-indigo-700 transition-colors"
                >
                  Send Message
                </button>
              </form>
            </motion.div>
          </motion.div>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-gray-900 text-white py-8 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto text-center">
          <p>&copy; 2024 AI Developer. All rights reserved.</p>
        </div>
      </footer>
    </div>
  );
}
